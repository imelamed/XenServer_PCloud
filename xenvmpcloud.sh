#!/bin/bash

# Script to create or delete a VM for DMSP-DHCP-Template
# This script can only run as Jenkins user on 135.248.4.152
#
# -c <description>                        Example: -c "Test VM" [create VM]
# -d <IP to delete>                       Example: -d 10.10.10.10 [destroy VM]
# -s <last 2 MAC octates> <description>   Example: -s 03:37 "Test VM" [create VM where the is allocated stataicly according to MAC]
#

RESULT=0
TEMPLATENAME=DMSP-DHCP-Nant-XSmall-RAM-4GB
NEWVMIP=
WAIT_FOR_VM=120

# Show usage message
function usage
{
        echo;echo "Usage: $0 -c <Description>"
        echo;echo "Usage: $0 -s <last of octests of MAC> <Description>"
        echo;echo "Usage: $0 -d <IP to delete>"
        echo Examples:
        echo -e $0 -c '"Test VM"' '\t\t' - Create Dynamic VM with Description "Test VM"
        echo -e $0 -d 10.10.10.10 '\t\t' - Delete VM with IP 10.10.10.10
        echo -e $0 -s 03:37 '"Test VM"' '\t' - Create VM with MAC ends with 03:37 to get static IP description "Test VM";echo
        RESULT=1
}

# Creating VM from template and getting its UUID
function create_vm_from_template
{
        NOW=$(date +"%F_%T")
        TMPVMNAME="$TEMPLATENAME-$NOW"

        # Create a VM from the template
        VMUUID=$(sudo xe vm-install new-name-label=$TMPVMNAME template=$TEMPLATENAME)
        return $?
}

# Finding VM interface and network UUID destroy it and recreate them with specific MAC Address
function change_vm_mac
{
        MAC2OCTS=$1

        # get VM interface UUID 
        VMVIFUUID=$(sudo xe vif-list vm-uuid=$VMUUID | grep -m1 uuid | cut -d: -f2 | awk '{ print $1}')

        # get VM network UUID
        VMVIFNETID=$(sudo xe vif-param-list uuid=$VMVIFUUID | grep network-uuid | cut -d: -f2 | awk '{ print $1}')
        sudo xe vif-destroy uuid=$VMVIFUUID
        sudo xe vif-create device=0 mac=e6:05:aa:db:$MAC2OCTS vm-uuid=$VMUUID network-uuid=$VMVIFNETID
}

# Starting the VM by its Temporary Name and waiting to get its IP
function start_vm
{
        COUNTER=1
        VMDESC=$1
        sudo xe vm-start vm=$TMPVMNAME
        if [ "$?" != "0" ]
        then
                RESULT=1
                return 1
        fi

        # Adding description to VM with time stamp
        sudo xe vm-param-set name-description=$TMPVMNAME uuid=$VMUUID
        if [ "$?" != "0" ]
        then
                RESULT=1
                return 1
        fi

        # Waiting $WAIT_FOR_VM seconds to get VM IP
        NEWVMIP=
        while [[ -z "$NEWVMIP" ]] && [[ "$COUNTER" -lt $WAIT_FOR_VM ]]
        do
                NEWVMIP=$(sudo xe vm-param-list uuid=$VMUUID | grep -i networks | cut -d: -f3 | awk '{ print $1}' | sed 's/;//')
                let COUNTER=COUNTER+1
                sleep 1
        done

        IS_IN_NET=$(echo $NEWVMIP | cut -d. -f1)
        VMHOSTNAME="Srv-"$(echo $NEWVMIP | sed 's/\./_/g')

        # If timout not passed
        if [ $COUNTER -lt $WAIT_FOR_VM ]
        then
                # Checking if a valid IP from network 135.X.X.X or 10.X.X.X
                if [ $IS_IN_NET = "135" ] || [ $IS_IN_NET = "10" ]
                then
                        #Editing the name of the VM
                        NEWVMNAME="$TEMPLATENAME-$NEWVMIP-$VMDESC"
                        sudo xe vm-param-set name-label="$NEWVMNAME" uuid=$VMUUID
                        if [ "$?" != "0" ]
                        then
                                RESULT=1
                                return 1
                        fi

                        # Editing the VM DIsk name and printing the IP of the VM
                        VDIUUID=$(sudo xe vbd-list vm-uuid=$VMUUID device=xvda | grep vdi | cut -d: -f2 | awk '{ print $1}')
                        sudo xe vdi-param-set name-label="$NEWVMNAME" uuid=$VDIUUID
                        if [ "$?" != "0" ]
                        then
                                RESULT=1
                                return 1
                        fi

                        # Checking if ssh is avliable to VM
                        COUNT=1
                        SSH_AVAILABLE=1

                        # Waiting for ssh to be avliable or timout of 20 seconds will exceed
                        while [[ $SSH_AVAILABLE != "0" ]] && [[ "$COUNT" -lt 20 ]]
                        do
                                sleep 1
                                sudo ssh -q -i /home/jenkins/.ssh/xenkins -o StrictHostKeyChecking=no -o BatchMode=yes xenkins@$NEWVMIP exit
                                SSH_AVAILABLE=$?
                                let COUNT=COUNT+1
                        done

                        # Checking if ssh is avliable if not destroy the VM.
                        if [ $SSH_AVAILABLE = "0" ]
                        then
                                echo -n $NEWVMIP $VMHOSTNAME
                                RESULT=0
                        else
                                # In case of ssh is not avaliable delete the VM
                                delete_vm_by_uuid
                                echo -n ERROR: VM IP is $NEWVMIP, but ssh to it failed. Zombie VM has been deleted
                                RESULT=1
                        fi
                else
                        # In case of time out or invalid IP. Delete the VM and report.
                        delete_vm_by_uuid
                        echo ERROR: Unable to get IP. Zombie VM has been deleted!
                        RESULT=1
                fi
        fi
}

# Delete VM
function delete_vm_by_uuid
{
        # Find VM Disk UUID and delete the VM and it's disk.
        VDIUUID=$(sudo xe vbd-list vm-uuid=$VMUUID device=xvda | grep vdi-uuid | cut -d: -f2 |  sed -e 's/^[ \t]*//')
        sudo xe vm-shutdown force=true uuid=$VMUUID
        sudo xe vm-destroy uuid=$VMUUID
        sudo xe vdi-destroy uuid=$VDIUUID
        RESULT=0
}

############################################
# Entry point

echo `date +"%F__%T"` ENTRY $0 $* $NEWVMIP >> /var/log/jenkins/actions_details.log

case "$1" in
        # Create and start a new VM with dynamic IP
        -c)
                create_vm_from_template
                echo `date +"%F__%T"` AFTER_create_vm_from_template $0 $* $NEWVMIP >> /var/log/jenkins/actions_details.log
                if [ "$?" == "0" ]
                then
                        start_vm "$2"
                        echo `date +"%F__%T"` AFTER_Start_vm $0 $* $NEWVMIP >> /var/log/jenkins/actions_details.log
                else
                        echo `date +"%F__%T"` FAILED_create_vm_from_template $0 $* $NEWVMIP >> /var/log/jenkins/actions_details.log
                        echo ERROR: Unable to create VM
                        RESULT=1
                fi
        ;;
        # Creating a VM with static IP by recreating the VM Interface with specific MAC
        -s)
                if [ $# -eq 3 ];
                then
                        create_vm_from_template
                        echo `date +"%F__%T"` AFTER_create_vm_from_template $0 $* $NEWVMIP >> /var/log/jenkins/actions_details.log
                        change_vm_mac "$2"
                        echo `date +"%F__%T"` AFTER_change_vm_mac $0 $* $NEWVMIP >> /var/log/jenkins/actions_details.log
                        start_vm "$3"
                        echo `date +"%F__%T"` AFTER_start_vm $0 $* $NEWVMIP >> /var/log/jenkins/actions_details.log
                else
                        usage
                fi
        ;;
        # Find the VM UUID to be deleted by its IP
        -d)
                if [ $# -eq 2 ];
                then
                        TEMP="networks="$(sudo xe vm-list params=networks | grep "$2;" | cut -d: -f2-10 |  sed -e 's/^[ \t]*//')
                        echo `date +"%F__%T"` DELETE_find_networks $TEMP $0 $* $NEWVMIP >> /var/log/jenkins/actions_details.log
                        VMUUID=$(sudo xe vm-list "$TEMP" | grep uuid | cut -d: -f2 |  sed -e 's/^[ \t]*//')
                        echo `date +"%F__%T"` DELETE_find_vmuuid $VMUUID $* $NEWVMIP >> /var/log/jenkins/actions_details.log
                        delete_vm_by_uuid
                        echo `date +"%F__%T"` DELETE_after_vm_delete $VMUUID $* $NEWVMIP >> /var/log/jenkins/actions_details.log
                        echo VM - $2 - Deleted!
                else
                        usage
                fi
        ;;
        # Not supported
        *)
                usage
        ;;
esac

NOW=`date +"%F__%T"`
echo $NOW $0 $* $NEWVMIP >> /var/log/jenkins/actions.log

exit $RESULT

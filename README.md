# XenServer_PCloud

Script to create or delete a VM for DMSP-DHCP-Template
This script can only run as Jenkins user on 135.248.4.152

 -c <description>                        Example: -c "Test VM" [create VM]
 -d <IP to delete>                       Example: -d 10.10.10.10 [destroy VM]
 -s <last 2 MAC octates> <description>   Example: -s 03:37 "Test VM" [create VM where the IP is allocated stataicly according to MAC]

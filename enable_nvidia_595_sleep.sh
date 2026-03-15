# Use these to check last boot journalctl
# journalctl -b -1 -e 
# journalctl -b -1 -k | grep -iE '(suspend|sleep|nvidia|acpi|freeze|oom|error)' | tail -n 50 

# Create a trapdoor that is >105% of VRAM (5070Ti 16GB = 16.8GB, 20GB is a safe number)
# This will be used to dump out VRAM to physical RAM for S3 deep sleep (D3Cold)
sudo mkdir -p /tmp_nvidia
grep -q "/tmp_nvidia" /etc/fstab || echo "tmpfs /tmp_nvidia tmpfs defaults,size=20G,mode=1777 0 0" | sudo tee -a /etc/fstab
systemctl daemon-reload
sudo mount -a

# Enable dumping of VRAM, point at the trapdoor, intercept kernel sleep calls
sudo grubby --update-kernel=ALL --args="nvidia.NVreg_PreserveVideoMemoryAllocations=1 nvidia.NVreg_TemporaryFilePath=/tmp_nvidia nvidia.NVreg_UseKernelSuspendNotifiers=1"

# Poke a hole in SELinux to allow systemd-sleep to actually write out the VRAM
# ALT 1: You've done all of the above, and SELinux failed, so just go build a new policy
sudo ausearch -c 'systemd-sleep' --raw | sudo audit2allow -M my-systemdsleep
sudo semodule -X 300 -i my-systemdsleep.pp

# ALT 2: Build from a raw .te that I generated using ALT 1
# ### my-systemdsleep.te
# module my-systemdsleep 1.0;

# require {
#         type tmp_t;
#         type systemd_sleep_t;
#         type tmpfs_t;
#         class capability2 perfmon;
#         class file { open read write };
# }

# #============= systemd_sleep_t ==============
# allow systemd_sleep_t self:capability2 perfmon;
# allow systemd_sleep_t tmp_t:file { open write };
# allow systemd_sleep_t tmpfs_t:file { open read write };
# ### EOF my-systemdsleep.te

# Untested commands, but should work
# checkmodule -M -m -o my-systemdsleep.mod my-systemdsleep.te
# semodule_package -o my-systemdsleep.pp -m my-systemdsleep.mod
# sudo semodule -X 300 -i my-systemdsleep.pp

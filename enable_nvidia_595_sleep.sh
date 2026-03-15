# This is a set of instructions for Fedora 43 attempting to run nVidia 595 drivers from Negativo17
# I ran into a problem where S3 sleep worked fine on 590, but the switch to 595 broke that ability.

# At least part of the issue was the switch from various nvidia daemons that ran under
# unbound permissions to using the native kernel daemon, which ultimately delegates operations to 
# systemd-sleep, which in turn does not have the correct permissions to write out the files.

# Further, the nVidia kernel checks if there is sufficient space at the target location
# /tmp by default is 1/2 RAM. That's 16GB in my case. It's also not empty. The desired amount of space
# to dump out VRAM is slightly larget than the VRAM. For a 5070Ti, that means the driver is looking for 
# >16GB available, even if it intends to dump out only a gig or two.
# I made a separate mem mount for it that is larger than the desired amount.
# Potential issue, of course, is if I try to sleep with a bunch of VMs up and VRAM loaded, I will OOM. 
# Don't do that. Alt, of course, write it to /var/tmp or some other disk, but I'm trading speed
# and SSD endurance here for ensurance of no issues.

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

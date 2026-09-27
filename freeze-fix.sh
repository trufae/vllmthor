#!/bin/sh 
# The strongest root cause is a known JetPack 7.0 / L4T R38.2.2 desktop freeze bug involving NVIDIA GPU PCIe power management—not CPU, RAM, or swap
#   exhaustion.
# 
#   Your board is running:
# 
#   - Jetson AGX Thor
#   - JetPack 7.0
#   - L4T R38.2.2
#   - Kernel 6.8.12-tegra
#   - NVIDIA GPU PCI power control: auto
# 
#   Your logs also show a second, independent problem: the USB mouse is repeatedly resetting through the Realtek hub.
# 
#   Evidence:
# 
#   - NVIDIA forum reports specifically describe Thor R38.2.2 freezing the desktop for several seconds. The recommended workaround is disabling GPU PCIe
#     runtime power management with:
# 
echo on | sudo tee /sys/bus/pci/devices/0000:01:00.0/power/control


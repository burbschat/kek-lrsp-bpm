# Scan the delay until a largeish signal is found. Not very sophisticated but indeed quite useful.

import pyrogue as pr
import numpy as np
import time

# Creat a Virtual Cient to connect to the Virtual Server via Zeromq
# client = pr.interfaces.VirtualClient(addr="130.87.81.129", port=9099)
client = pr.interfaces.VirtualClient(addr="localhost", port=9099)  # Adjust this to your setup!

# Pointer to client root
root = client.Root


def trigger_and_wait():
    root.RFSoC.Application.ReadoutCtrl.TrigInArm.set(1)
    # Wait while not idle (state 0)
    # Not very smart, but works.
    while not root.RFSoC.Application.ReadoutCtrl.stateReg.get() == 0:
        time.sleep(0.01)


# Examine the noise floor to determine a threshold value
trigger_and_wait()
mean_noise_std = np.array([root.SoftwarePositionCalculation.WaveformData[chan].get().std() for chan in range(4)]).mean()

# Set the threshold at 10 times the mean standard deviation
threshold = 10 * mean_noise_std


delay_step_ns = 800  # Around the buffer length should be suitable
delay_ns = delay_step_ns
max_val = 0

# Injection point delays are slighly above 113us so make sure we can cover that
# range at least.
while delay_ns < 300 * 1000:
    print(delay_ns / 1000)
    root.RFSoC.Application.ReadoutCtrl.TrigRingBufDly.set(delay_ns / 1000)  # Variable is in us
    delay_ns += delay_step_ns
    trigger_and_wait()

    for j in range(4):
        max_val = max(max_val, np.absolute(root.SoftwarePositionCalculation.WaveformData[j].get()).max())

    print(f"Attempted delay {hex(delay_ns)} ns, found max absolute signal value of {max_val}")

    if max_val > threshold:
        print(f"Found a signal with absolute value larger than {threshold}. Stopping.")
        break

exit()

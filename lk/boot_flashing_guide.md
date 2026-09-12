#### Prerequisites (Host Workstation)

 - fastboot (Android Platform Tools)
 - img2simg (from android-sdk-libsparse-utils or AOSP build tools)

 --------------------------------------------------------------------------------

#### Step 1: Prepare and Convert the Boot Image

 Ensure the patched boot image is padded/sized appropriately (≤ 32 MiB) and convert it to an Android Sparse Image:

 ```bash
# Verify the raw image starts with standard Android boot magic
head -c 8 magisk-patched-boot.img   # Should display 'ANDROID!'

# Convert raw boot image to Android sparse format
img2simg magisk-patched-boot.img magisk-boot.simg
 ```

 --------------------------------------------------------------------------------

#### Step 2: Enter LK Fastboot Mode

Use provided script or other documented methods.
Device will show a black screen with only "Fastboot:>" at the bottom of the screen in LK fastboot mode.

#### Step 3: Verify Unlock Status in LK

 Query the LK unlock variable to ensure the lock policy is inactive:

 ```bash
fastboot getvar unlock_status
 ```

 - Expected Output: unlock_status: true (or unlock_status: yes).

 --------------------------------------------------------------------------------

#### Step 4: Flash the Sparse Boot Image

 Flash the sparse .simg image to the boot partition:

 ```bash
fastboot flash boot magisk-boot.simg
 ```

 - Expected Output:
   ```text
Sending 'boot' (...)               OKAY [  ...]
Writing 'boot'                     OKAY [  ...]
Finished. Total time: ...
   ```

 --------------------------------------------------------------------------------

#### Step 5: Reboot Device

```bash
fastboot reboot
```

#### Step 6: Confirm magisk shows ramdisk installed and magisk shell su is available.
# Fire 7 unlock by MeisterLone (Packaged for HackerOne proof testing)
https://github.com/MeisterLone

Release: `fire-unlock-1.0`

Unlock package for the Fire 7 (12th generation), code name `quartz`. The executable is one self-contained Python 3
program. It talks directly to an ADB-attached tablet, embeds all native exploit payloads, and derives all
per-tablet material on the tablet. RPMB KEY!

Im obligated to say; use this only on a device you are willing to lose. `--execute` deliberately changes
authenticated RPMB as well as an IDME region - both regions are validated during normal boot sequence. A power loss during a
write operation means guaranteed device brick but the exploit is deliberately designed to NOT write when something isnt exactly as they were on my two test devices.
The entire 24 KB IDME as well as the entire RPMB write sequence both need to complete successfully before reboot. If either of them dont, its either brick or boot loop.
Boot loop is recoverable via LK fastboot, which you can enter on this device 

## Package contents

- `unlock.py` - controller plus compressed ARM32 exploit bootstrap, carrier code for RPMB write, exploit kernel
  module, read-only job, and commit job.
- `README.md` - this doc and research reference.
- `ota/` - location for official full OTA files; OTAs not included. Download from the official AMZ repo only.
- `lk/fastboot_unlock_probe.sh` - development script- can use to enter LK fastboot mode directly, might be useful in a boot loop scenario.
- `lk/boot_flashing_guide.md` - guide to flashing patch boot.img (magisk/persistent root guide)

The only host runtime dependencies are Python 3.9 or newer and `adb`. No NDK,
compiler, root shell, PyUSB, fastboot, repository checkout, or Python package
is needed. (fastboot_unlock_probe does need additional dependencies, but its not needed for this unlock.)

## Scope and qualification

The controller is serial-agnostic and per-device-data-agnostic, not
kernel-agnostic. Kernel addresses and module modversions cannot be discovered
safely before privilege, so an exact known OTA/kernel profile remains a hard
admission requirement. Supplying an unknown or incorrect OTA likely means the exploit never completes.
There is no brick risk BEFORE the UAF race success and the race success depends on exact offsets, so I have made provisions for mitigating brick risk. 
It might be overly defensive to this regard, unlock is likely possible despite some checks failing. If you run the target live-verified build, checks will pass and unlock will succeed.

Therefore; best chance for success is to update your Fire 7 HD using the exact OTA from the official amazon repo; update-Fire_7_12th_Gen-RS8338.bin
At the time of writing, that was downloaded from;
https://fireos-tablet-src.s3.us-west-2.amazonaws.com/4amHNOvwW4KDYd5xDz75MnJ9nn/update-Fire_7_12th_Gen-RS8338_user_3339_0030132734852.bin

Supported exact builds are:

| Fire OS build | Payload profile | Qualification |
|---|---|---|
| RS8324.2314N | RS8324      | OTA-derived, best effort / AI derived conversion |
| RS8327.2526N | current ABI | OTA-derived, best effort / AI derived conversion |
| RS8328.3033N | current ABI | OTA-derived, best effort / AI derived conversion |
| RS8331.2608N | current ABI | OTA-derived, best effort / AI derived conversion |
| RS8332.3115N | current ABI | OTA-derived, best effort / AI derived conversion |
| RS8333.2734N | current ABI | OTA-derived, best effort / AI derived conversion |
| RS8338.3339N | current ABI | live proven 

All seven official full OTAs were checked for their exact metadata,
`boot.img` digest, and common audited LK digest. RS8338 is the only build live verified with unlock success, on two complete separate devices. 

## Before running

1. Charge the tablet, boot Fire OS normally, enable USB debugging, accept the
   host key, and keep USB connected directly to the host.
2. Zero other memory-heavy work on the tablet. The exploit depends on memory stability and holds
   about 300 MB while establishing its expoit primitive.
3. Put exactly one official **full** OTA for the tablet's installed build in
   `ota/`. Either `.bin` or `.zip` is accepted. Do not rename or unpack it.
4. Ensure `adb devices -l` shows the tablet in `device` state (authorized)

The script selects exactly one online `quartz` tablet. 

## Commands

Read-only end-to-end qualification:

```sh
python3 unlock.py --probe-only --output audit-probe
```

One-shot probe followed by the authorized unlock transition:

```sh
python3 unlock.py --execute --output audit-unlock
```

Useful options:

```text
--ota-dir DIR            OTA directory; default is ./ota beside unlock.py
--serial SERIAL          select one ADB transport when needed
--output DIR             new host output directory; it must not already exist
--max-clean-misses N     0 means retry classified clean UAF misses indefinitely
--reuse-server           emergency/recovery reuse of this release's live server
--self-test              decode and hash every embedded native component
```

`--execute` already performs the full authenticated probe before it starts the
commit job. A separate `--probe-only` run is optional and requires another UAF
bootstrap later unless its resident server is deliberately reused.

## What the script does

Before any kernel exploit, the host controller requires:

- exactly one selected online `quartz` device connected;
- an exact supported build fingerprint and exact kernel banner;
- the 32/64-bit ABI pair, enforcing SELinux, and required device topology;
- exactly one full OTA whose metadata matches the live fingerprint;
- the profile's exact `boot.img` hash; and
- the audited LK image hash and unlock-policy tuple.

For each UAF attempt it then requires a changed boot ID, normal boot reason,
and at least 70 seconds of stable uptime. It derives the boot-local
`u:r:init:s0:c1023` SID from live sidtab insertion accounting, stages and
hashes the embedded profile payloads, and starts the UAF/bootstrap.

The privileged read-only job then:

1. reads and structurally parses the live 24 KiB IDME image;
2. finds unique `dev_flags`, `fos_flags`, and `usr_flags` records and creates a
   target by changing only those named value bytes;
3. uniquely identifies `rpmb_svc` by process, thread, start-time, command-line,
   executable, and executable hash constraints;
4. temporarily borrows the live `tee` SID;
5. reads the attached eMMC CID and asks the Crypto TA to derive that tablet's
   RPMB key;
6. authenticates a fresh RPMB counter and logical block-0 read; and
7. restores the TEE SID and zeroes CID/key buffers.

The raw CID, derived key, RPMB frames, and raw IDME image never leave the
native tablet process and are not written to disk.

The probe executable has the persistent-write code compiled out. In execute
mode, a second independently hashed job rechecks the same constraints, stops
the exact `rpmb_svc`, takes another fresh authenticated counter/block read,
and performs only the required missing transitions (only when needed, logic is indempotent):

1. one authenticated reliable RPMB `NZMA` to `AMZN` write; (Engineering mode, activated, but we're still boot-looped if we stop here.)
2. authenticates RPMB + readback;
3. one synchronous/direct whole-image IDME write derived from the live image (allows boot to progress)
4. full IDME readback and patched flags validation;
5. final authenticated RPMB readback;
6. restoration of `force_ro=1`, all SID leases, and the original service.

Once the commit job starts, Ctrl-C is deferred until its cleanup/result path
finishes. A temporary ADB/socket interruption causes the host to reconnect and
collect the on-tablet result rather than cancel the transaction, intentional attempt to mitigate brick or boot-loop.

## Persistent-state matrix

| Authenticated RPMB | Parsed IDME | Action |
|---|---|---|
| `NZMA` | `DEV0/FOS0/USR0` | Perform both transitions. |
| `AMZN` | `DEV40/FOS80/USR0` | Already unlocked; perform no write. |
| `AMZN` | `DEV0/FOS0/USR0` | Recovery state; finish IDME only.  |
| `NZMA` | `DEV40/FOS80/USR0` | Recovery state; finish RPMB only. (Extremely unlikely state, but might as well have this mechanism. |
| anything else | anything else | Refuse; no guessed repair and no reboot. |

Success requires authenticated `AMZN`, exact live-derived IDME target,
`rpmb_svc` running, SID restoration, and `force_ro` restoration.

The script does NOT automatically reboot after success.

## UAF retries and physical recovery

A logged marker saying `no pivot - hard exit` is the only ordinary clean UAF
miss. Another UAF race attempt is not attempted after a hard exit, runtime state is corrupted/unpredictable- Script does a fresh reboot and another attempt.
The default has no clean-miss limit.

If the UAF pivots but a later safety check fails, the exploit
parks intentionally: killing it could release a repurposed kernel page. The
controller requests a reboot and waits for a changed boot ID. These tablets
can wedge Android reboot requests in this state. When the script prints
`waiting for a physical power cycle`, hold Power until the tablet turns off,
boot it normally with USB attached, and leave the same script running. It
will require a new normal boot, 70 seconds of uptime, and then continue. NEVER
kill `bootstrap`, `arbwmain`, or `arbwNNN` processes manually.

A panic/watchdog boot reason, unexplained reset, unclassified exploit ending,
or changed transport is a hard stop for the script and it wont retry.
In this case, get the tablet booted back up normally and retry the script. 
A second reboot may be necessary to clear the 'panic' reboot reason.

## Failure and recovery rules

Admission, OTA, SID, module, CID, Crypto TA, RPMB authentication, IDME parser,
device identity, service identity, state, cleanup, or readback drift causes 
the exploit code to exit, before the commit job, which means no write was
attempted and therefore virtually eliminating brick risk.

If `--execute` reports an error after `job_started` for the commit, 
**do not reboot and do not rerun the exploit**.
Immediately after the UAF race success, always, a temporary resident kernel module "server" is injected.
that module performs the persistent unlock/exploit logic and also accepts remote commands. 
This same module can be used to recover state using the following command;

```sh
python3 unlock.py --probe-only --reuse-server --output recovery-probe
```

`--reuse-server` accepts only this release's exact server build and a verified
resident server. If that recovery probe is unavailable or returns an
unknown state, stop and audit the tablet manually. The script never reboots an
unknown post-write state, to leave me with the oportunity to perform a recovery.

This mechanism was heavily used during exploit development and I am keeping it in this
PoC as a demonstration, I dont actually think this would ever necessarily be used, considering the 
brick risk mitigation in the exploit stages.

After a successful probe-only run, the tablet remains unchanged persistently
but the volatile module/exploit supervisor remains until reboot. Reboot when
you no longer need `--reuse-server`. 

After a successful execute run, the unlock is complete.
Now is **the critical moment!**. Reboot manually to find out if your bootloader accepts the new RPMB state.

## Output directory

The selected output directory is created before work begins. It contains:

- `report.json` - final machine-readable result, written even on a handled
  failure;
- `events.jsonl` - fsync'd chronological controller events;
- `bootstrap.log` - successful UAF/bootstrap transcript, when this invocation
  created the server;
- `bootstrap-status.log` - successful server status transcript;
- `bootstrap-attempt-N.log` - archived clean-miss or post-pivot refusal logs;
  and
- `bootstrap-attempt-N.status.log` - status companion when one existed.

`report.json` includes release/mode/timestamps, the ADB routing serial, profile
and qualification, exact OTA/boot/LK hashes, live preflight facts, active boot
ID, success/verdict/error, and the probe/commit result. Each job result records:

- compile-time write enablement, status, last stage, and before/after state;
- RPMB magic value, counter, logical-record hashes, device major/minor, write flag,
  and write status;
- IDME table count/end, three parsed offsets, image hashes, device major/minor,
  write flag, and write status;
- `rpmb_svc` PID/state/hash and stop/resume attempts/status; and
- TEE/wipe SID and `force_ro` cleanup status.

A cleanup field of `-1` in probe-only output means that resource was never
acquired, not that restoration failed. Counter values, hashes, offsets, device
numbers, and process IDs are diagnostic metadata. Output files intentionally
exclude the RPMB key, raw CID, raw RPMB frames, raw IDME bytes, and exploit protocol.

Exit status is 0 only for `probe-verified` or `unlock-verified`. A controlled
admission/runtime refusal returns 1. Command-line misuse returns 2.

## LK confirmation

`adb reboot fastboot` enters userspace fastbootd (no system partition write possible here by default, 
I have a fastbootd patcher that makes it allow write to any partition on this family, not included in this package, out of scope for HackerOne proof.
Use the physical LK-entry sequence (both volume buttons held while connecting USB (fastboot_unlock_probe.sh or select reboot to bootloader in userspace fastbootd)

Conclusive unlock status proof;
```sh
fastboot getvar unlock_status
```

## Persistent root

Enter LK via either of the two methods. Execute fastboot `dump:boot` read is an additional unlock confirmation, but also necessary for persistent root.

If dump:boot succeeds, unlock was successful and persistent and LK fastboot mode now also allows write. (only small writes if I recall correctly)
 - Save boot.img as stock backup somewhere and also upload it to device internal storage via adb once booted.
 - Stream install the latest magisk apk and on-device use it to patch boot.img (install button)
 - Download the patched magisk-patched-boot.img off device and save it locally. 

Flash the patched boot.img using boot_flashing_guide.md

## Support

This unlock is free and always will be. If it saved you some time, or rescued a
tablet from the junk drawer, you can buy me a coffee by scanning the code below.
Completely optional - thanks either way.

<p align="center">
  <img src="assets/bmc-qr.png" width="250" alt="Buy Me a Coffee QR code">
</p>



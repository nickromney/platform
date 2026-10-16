# Runtime isolation

Verification of the Compose platform must preserve other running Docker workloads, including kind containers sharing Docker Desktop.

## Sub-features

- Capture full container IDs, running state and start times before launch.
- Compare every captured workload after Compose cleanup; missing, stopped or restarted containers fail.
- Retain ownership after cleanup failure so retry remains possible.

## How to get to it (user POV)

Run the Compose verification lifecycle while an unrelated workload is already running. The workload must remain running with its original identity and start time after cleanup.

## Driving it with control.sh

`control.sh --execute launch` records `unrelated-containers.before.txt` in the run evidence. `control.sh --execute cleanup` performs teardown and writes `unrelated-containers.after.txt`; success requires every baseline entry to match Docker's independent inspect response.

For a bounded boundary check, use executable `scripts/runtime-snapshot.sh capture SNAPSHOT`, remove only a disposable workload started after capture, then `scripts/runtime-snapshot.sh assert SNAPSHOT`. A separate owned sentinel included in the baseline must cause assert to fail when stopped. Retain both positive and negative output alongside the snapshot. Use cached images, explicit resource limits and no network; never stop a preexisting workload for the negative case.

## Gotchas

This gate proves container preservation at the lifecycle boundary, not application health inside the container. Starting unrelated workloads after capture does not add them to the baseline. Do not claim full Compose proof from a disposable-container boundary check. Kind/Lima reset, stage-900 acceptance and optional-feature enabled/disabled resource matrices remain separate pending infrastructure verification.

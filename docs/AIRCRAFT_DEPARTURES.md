# Aircraft departure corridors

Departure direction is authored per stand. Coastal and northern airports tow nose-first away from the terminal facade; night A1 exits nose-first into the foreground, night A2 pushes tail-first to the open right side. The upper forward-tow stand waits for A1 to vacate its shared wing-clearance corridor.

Aircraft and tug share one eased trajectory aligned to the aircraft axis. The towbar attaches at the calibrated nose wheel; shadow and depth ordering move with the aircraft. Foreground departure progress interpolates between simulation ticks. Endpoint is beyond the current viewport by 180 world units, so neither the tail nor tug disappears inside the scene. After handoff, the tug follows an off-screen perimeter link and enters the service base through the existing road portal.

Verified: all campaign missions, direction selection, shared-corridor interlock, constant aircraft/tug offset and full offscreen clearance at portrait and landscape sizes.

41 tests passed; analyzer clean; web release built. Published version 5, commit bc5d3de5726c454a30bcc9977eac45f1010b5f5a; deployment appgdep_6abcc5b1bac481918d34496ed7dfa814 succeeded.

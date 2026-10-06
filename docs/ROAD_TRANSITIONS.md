# Airport roads and screen transitions

Routes now have explicit base, apron and off-screen transit sections. Portal endpoints lie 180 world units beyond the current screen edge; only the actual viewport clips vehicles. Displayed poses and lane markings share quadratic fillets. Main roads use straight or obtuse junctions, with up to 70-unit tangent cutbacks; concrete service approaches use painted guide lines. Road geometry is cached by area and viewport. Portal traversal has a minimum logical duration independent of viewport size.

Buses use off-lane pockets and wait for ground vehicles to clear their flight before dispatch. Schedules were adjusted for entry/exit travel time. Six campaign missions remain completable on time.

Validation: every base-to-stand and return transition in three airport layouts at three viewport sizes is fully offscreen when visibility changes. Visible route junctions have no acute switchbacks and preserve position/tangent direction through fillets. Existing traffic, campaign and phone UI tests retained.

38 tests passed; analyzer clean; release web build passed. Published version 4: commit 348a0e904a048f30cd428a194265bebbeb9b717a, deployment appgdep_6abbfb95c4848191b5cd876120802634 succeeded.

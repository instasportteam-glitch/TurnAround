import 'dart:ui' as ui;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'game/player_profile.dart';
import 'profile_screen.dart';
import 'l10n/strings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game/airport_game.dart';
import 'game/shift.dart';
import 'game/apron_bus.dart';
import 'game/missions.dart';
import 'game/campaign.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const TurnaroundApp());
}

const violet = Color(0xff9872ff);
const cyan = Color(0xff75d8ff);
const muted = Color(0xff95a3c6);
const panel = Color(0xff141e39);

class TurnaroundApp extends StatefulWidget {
  const TurnaroundApp({super.key});
  @override
  State<TurnaroundApp> createState() => _TurnaroundAppState();
}

class _TurnaroundAppState extends State<TurnaroundApp> {
  final profile = PlayerProfile();
  @override
  void initState() {
    super.initState();
    profile.load();
  }

  @override
  void dispose() {
    profile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: profile,
    builder:
        (context, _) => MaterialApp(
          locale: Locale(profile.language),
          supportedLocales: const [Locale('en'), Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          title: 'Turnaround',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xff080e22),
            colorScheme: ColorScheme.fromSeed(
              seedColor: violet,
              brightness: Brightness.dark,
            ),
            fontFamily: 'Arial',
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff7651e9),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          home: GameScreen(profile: profile),
        ),
  );
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.profile});
  final PlayerProfile profile;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late Shift shift;
  late AirportGame game;
  bool briefing = true;
  bool started = false;
  int selected = 0;
  int missionIndex = 0;
  final campaign = Campaign();
  bool missionMenu = false, recorded = false;
  bool campaignLoaded = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reset();
    campaign.load().then((_) {
      if (mounted) setState(() => campaignLoaded = true);
    });
  }

  void reset() {
    shift = Shift(mission: Mission.all[missionIndex])..paused = true;
    recorded = false;
    missionMenu = false;
    selected = 0;
    briefing = true;
    started = false;
    game = AirportGame(shift, () {
      if (!mounted) return;
      if (shift.finished && !recorded && campaignLoaded) {
        recorded = true;
        widget.profile.record(shift);
        campaign.record(missionIndex, shift.stars).then((_) {
          if (mounted) setState(() {});
        });
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !shift.finished) {
      setState(() => shift.paused = true);
    }
  }

  void select(int index, {bool focus = true}) => setState(() {
    selected = index;
    game.selected = index;
    if (focus) game.focusGate(index);
  });

  @override
  Widget build(BuildContext context) {
    final flight = shift.flights[selected];
    game.language = widget.profile.language;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: double.infinity),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.flight_takeoff,
                            color: violet,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: LText(
                                'TURNAROUND',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                          const Icon(Icons.schedule, size: 15, color: cyan),
                          const SizedBox(width: 5),
                          LText(clockText(shift.timeLimit - shift.elapsed)),
                          const SizedBox(width: 8),
                          LText(
                            '${shift.onTime}/${shift.flights.length}',
                            style: const TextStyle(color: cyan),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: GameStrings.of(context).tr('Missions'),
                            icon: const Icon(Icons.map_outlined, size: 20),
                            onPressed:
                                () => setState(() {
                                  shift.paused = true;
                                  missionMenu = true;
                                }),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: GameStrings.of(context).tr('Pause'),
                            onPressed:
                                !started || shift.finished
                                    ? null
                                    : () => setState(() => shift.paused = true),
                            icon: const Icon(Icons.pause_rounded),
                          ),
                          const SizedBox(width: 38),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: GameWidget(
                                game: game,
                                key: ObjectKey(game),
                              ),
                            ),
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTapUp:
                                    (details) => select(
                                      game.gateAt(
                                        details.localPosition.dx,
                                        details.localPosition.dy,
                                      ),
                                      focus: false,
                                    ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xdd292541),
                                  minimumSize: const Size(40, 40),
                                ),
                                onPressed:
                                    () => setState(() {
                                      game.simulationSpeed =
                                          game.simulationSpeed == 1
                                              ? 2
                                              : game.simulationSpeed == 2
                                              ? 3
                                              : 1;
                                    }),
                                child: LText('×${game.simulationSpeed}'),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final index in [
                                    for (var i = 0; i < game.sceneCount; i++) i,
                                    -1,
                                  ])
                                    ChoiceChip(
                                      visualDensity: VisualDensity.compact,
                                      label: LText(
                                        game.sceneTitle(index),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      selected: game.sceneIndex == index,
                                      onSelected: (_) {
                                        if (index < 0) {
                                          setState(game.focusBase);
                                        } else {
                                          select(index == 0 ? 0 : index + 1);
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xaa0b142a),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(8),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: LText(
                                    shift.gustActive
                                        ? 'GUSTS · VEHICLES SLOWER'
                                        : shift.mission.weather,
                                    style: TextStyle(fontSize: 9, color: muted),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (shift.tasks.any((t) => t.spec.gate == selected))
                      SizedBox(
                        height: 39,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          children:
                              shift.tasks.where((t) => t.spec.gate == selected).map((
                                task,
                              ) {
                                final reason = shift.taskBlocked(task);
                                final status =
                                    task.done
                                        ? task.spec.validFor > 0
                                            ? '✓ ${clockText((task.spec.validFor - (shift.elapsed - task.completedAt!)).clamp(0, task.spec.validFor))}'
                                            : '✓'
                                        : task.active
                                        ? '${(task.progress * 100).round()}%'
                                        : reason ?? 'Start';
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: LTooltip(
                                    message: reason ?? 'Assign dispatch crew',
                                    child: OutlinedButton(
                                      onPressed:
                                          reason == null
                                              ? () => setState(() {
                                                shift.startTask(task);
                                              })
                                              : null,
                                      child: LText(
                                        '${task.spec.title} · $status',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: task.done ? cyan : muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: shift.flights.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder:
                            (context, i) => ChoiceChip(
                              showCheckmark: false,
                              selected: selected == i,
                              onSelected: (_) => select(i),
                              label: LText(
                                'A${i + 1} · ${shift.flights[i].code}${shift.flights[i].departed ? ' ✓' : ''}',
                              ),
                              selectedColor: const Color(0xff453178),
                              backgroundColor: panel,
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.airplanemode_active,
                            color: cyan,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LText(
                                  flight.code,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                  ),
                                ),
                                LText(
                                  flight.departed
                                      ? 'Aircraft departed'
                                      : flight.ready
                                      ? flight.jobs[Service.tug] !=
                                              JobState.waiting
                                          ? 'Towing…'
                                          : shift.blocked(
                                                flight,
                                                Service.tug,
                                              ) ??
                                              'Ready for towing'
                                      : 'Assign ground services',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          LText(
                            flight.departed
                                ? '✓'
                                : '${shift.elapsed > flight.deadline ? '+' : ''}${clockText((flight.deadline - shift.elapsed).abs())}',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color:
                                  shift.elapsed > flight.deadline &&
                                          !flight.departed
                                      ? Colors.orangeAccent
                                      : cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children:
                            Service.values
                                .where((s) => s != Service.tug)
                                .map(
                                  (s) =>
                                      Expanded(child: serviceCard(flight, s)),
                                )
                                .toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              shift.blocked(flight, Service.tug) == null
                                  ? () => setState(
                                    () => shift.dispatch(flight, Service.tug),
                                  )
                                  : null,
                          icon: const Icon(Icons.flight_takeoff, size: 20),
                          label: LText(
                            flight.departed
                                ? 'FLIGHT DEPARTED'
                                : flight.jobs[Service.tug] == JobState.waiting
                                ? 'DEPART'
                                : 'TOWING…',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (briefing && !missionMenu) overlay(briefingCard()),
                if (!briefing &&
                    shift.paused &&
                    !shift.finished &&
                    !missionMenu)
                  overlay(pauseCard()),
                if (shift.finished && !missionMenu) overlay(resultCard()),
                if (missionMenu) overlay(missionsCard()),
                Positioned(top: 4, right: 8, child: profileButton()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openProfile() async {
    final wasPaused = shift.paused;
    setState(() => shift.paused = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileScreen(profile: widget.profile),
    );
    if (mounted) {
      setState(() {
        if (!wasPaused &&
            !shift.finished &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          shift.paused = false;
        }
      });
    }
  }

  Widget profileButton() => IconButton(
    tooltip: GameStrings.of(
      context,
    ).tr(widget.profile.loaded ? 'Profile' : 'Loading profile…'),
    onPressed: widget.profile.loaded ? openProfile : null,
    icon: PlayerAvatar(
      name: widget.profile.name,
      bytes: widget.profile.avatar,
      radius: 15,
    ),
  );

  Widget stat(String title, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff293552)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            title,
            style: const TextStyle(fontSize: 8, letterSpacing: 1, color: muted),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(icon, size: 12, color: cyan),
              const SizedBox(width: 4),
              Expanded(
                child: LText(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget serviceCard(Flight f, Service s) {
    final state = f.jobs[s]!;
    final vehicle = shift.vehicles[s]!;
    final done = state == JobState.done;
    final queued = state == JobState.queued;
    final active = state == JobState.driving || state == JobState.working;
    final blocked = shift.blocked(f, s);
    final status = switch (state) {
      JobState.waiting =>
        s == Service.bus && blocked != null
            ? 'After services'
            : s == Service.cater && f.jobs[Service.clean] != JobState.done
            ? 'After cleaning'
            : vehicle.flight != null || vehicle.returning > 0
            ? 'Queue'
            : 'Assign',
      JobState.queued => 'Cancel',
      JobState.driving =>
        vehicle.preparing
            ? 'Preparing'
            : vehicle.trafficWaiting
            ? 'Yielding'
            : 'En route',
      JobState.working => '${(f.progress[s]! * 100).round()}%',
      JobState.done =>
        vehicle.flight == f && vehicle.phase == VehiclePhase.returning
            ? 'Leaving'
            : 'Done',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: LTooltip(
        message:
            vehicle.flight == f && vehicle.trafficWaiting
                ? vehicle.waitReason
                : queued
                ? 'Tap to remove from queue'
                : blocked ?? 'Assign: ${s.label}',
        child: Material(
          color:
              done
                  ? const Color(0xff123c3e)
                  : active || queued
                  ? const Color(0xff382b65)
                  : panel,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap:
                queued
                    ? () => setState(() => shift.cancel(f, s))
                    : blocked == null
                    ? () => setState(() => shift.dispatch(f, s))
                    : null,
            child: Container(
              height: 86,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: active || queued ? violet : const Color(0xff30415f),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: SizedBox(
                      height: 38,
                      width: 72,
                      child:
                          s == Service.bus
                            ? const CustomPaint(painter: BusCardPainter())
                            : game.fleet == null
                            ? const SizedBox.shrink()
                            : CustomPaint(
                              painter: FleetCardPainter(game.fleet!, s.index),
                            ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: LText(
                      s == Service.bus ? 'Bus' : s.label,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  LText(
                    status,
                    style: const TextStyle(fontSize: 8, color: muted),
                    maxLines: 1,
                  ),
                  if (active)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: LinearProgressIndicator(
                        value: f.progress[s],
                        color: violet,
                        minHeight: 2,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget overlay(Widget content) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xd9080d20),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: const Color(0xff141d38),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xff4b3c7b)),
            ),
            child: content,
          ),
        ),
      ),
    ),
  );

  Widget missionsCard() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const LText(
        'MISSION MAP',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
      ),
      LText(
        '3 airports · 6 missions · ${campaign.stars}/18 stars',
        style: const TextStyle(color: cyan, fontSize: 12),
      ),
      const SizedBox(height: 10),
      const LText(
        'Dispatch every flight to unlock the next mission. Earn three stars by leaving on time without repeating de-icing.',
        style: TextStyle(color: muted, fontSize: 11),
      ),
      for (final mission in Mission.all)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: panel,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap:
                  campaignLoaded && campaign.unlocked(mission.id)
                      ? () => setState(() {
                        missionIndex = mission.id;
                        reset();
                      })
                      : null,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/images/${mission.asset}',
                        width: 54,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LText(
                            '${mission.id + 1}. ${mission.title}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          LText(
                            mission.airport,
                            style: const TextStyle(color: muted, fontSize: 10),
                          ),
                          LText(
                            'Aircraft: ${mission.deadlines.length} · Tasks: ${mission.tasks.length} · ${clockText(mission.seconds)}',
                            style: const TextStyle(color: muted, fontSize: 10),
                          ),
                          if (campaign.unlocked(mission.id))
                            Row(
                              children: List.generate(
                                3,
                                (i) => Icon(
                                  i < campaign.best[mission.id]
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 14,
                                  color: cyan,
                                ),
                              ),
                            )
                          else
                            LText(
                              'After mission ${mission.id}',
                              style: const TextStyle(color: cyan, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      campaign.unlocked(mission.id)
                          ? Icons.chevron_right
                          : Icons.lock_outline,
                      size: 18,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      if (campaign.saveFailed)
        const LText(
          'Could not save progress on this device.',
          style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
        ),
      Center(
        child: TextButton(
          onPressed: () => setState(() => missionMenu = false),
          child: const LText('BACK'),
        ),
      ),
    ],
  );

  Widget briefingCard() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.flight_takeoff_rounded, size: 40, color: violet),
      const SizedBox(height: 20),
      LText(
        '${shift.mission.airport.toUpperCase()} · MISSION ${missionIndex + 1}',
        style: TextStyle(fontSize: 10, letterSpacing: 2, color: cyan),
      ),
      const SizedBox(height: 10),
      LText(
        shift.mission.title,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      const SizedBox(height: 20),
      LText(
        '${shift.mission.brief}\n\nShift: ${clockText(shift.timeLimit)}. Flights to dispatch: ${shift.flights.length}.',
        style: TextStyle(color: muted, height: 1.5),
      ),
      const SizedBox(height: 14),
      const LText(
        '01   Start baggage, fuel and cleaning together.\n02   Catering comes after cleaning.\n03   Bus after services. Then tap DEPART.',
        style: TextStyle(fontSize: 12, height: 1.9),
      ),
      const SizedBox(height: 14),
      const LText(
        'Vehicles follow service roads, yield on narrow sections and slow near aircraft. Towing starts only when the stand is clear.',
        style: TextStyle(color: muted, fontSize: 11, height: 1.5),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed:
              () => setState(() {
                briefing = false;
                started = true;
                shift.paused = false;
              }),
          child: const LText('START SHIFT'),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: () => setState(() => missionMenu = true),
          child: const LText('CHOOSE MISSION'),
        ),
      ),
    ],
  );

  Widget pauseCard() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.pause_circle_outline, color: violet, size: 44),
      const SizedBox(height: 16),
      const LText(
        'Shift paused',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      const LText(
        'Timers and vehicles are stopped.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => setState(() => shift.paused = false),
          child: const LText('RESUME'),
        ),
      ),
      TextButton(
        onPressed: () => setState(() => missionMenu = true),
        child: const LText('Mission map'),
      ),
      TextButton(
        onPressed: () => setState(reset),
        child: const LText('Restart'),
      ),
    ],
  );

  Widget resultCard() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          3,
          (i) => Icon(
            i < shift.stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 44,
            color: i < shift.stars ? const Color(0xffffd28a) : muted,
          ),
        ),
      ),
      const SizedBox(height: 14),
      LText(
        shift.stars == 3
            ? 'Perfect shift'
            : shift.completed > 0
            ? 'Shift complete'
            : 'Try again',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 20),
      LText(
        'Departed: ${shift.completed} / ${shift.flights.length}\nOn time: ${shift.onTime} / ${shift.flights.length}\nShift credits: ${shift.credits}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: muted, height: 1.8),
      ),
      const SizedBox(height: 18),
      const LText(
        'Tip: start cleaning early to leave enough time for catering.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: muted, height: 1.5),
      ),
      if (shift.stars >= 2 && missionIndex + 1 < Mission.all.length)
        FilledButton(
          onPressed:
              () => setState(() {
                missionIndex++;
                reset();
              }),
          child: const LText('NEXT MISSION'),
        ),
      TextButton(
        onPressed: () => setState(() => missionMenu = true),
        child: const LText('MISSION MAP'),
      ),
      if (campaign.saveFailed)
        const LText(
          'Progress will be lost when the game closes.',
          style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
        ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => setState(reset),
          child: const LText('REPLAY MISSION'),
        ),
      ),
    ],
  );
}

class FleetCardPainter extends CustomPainter {
  FleetCardPainter(this.image, this.row);
  final ui.Image image;
  final int row;
  @override
  void paint(Canvas canvas, Size size) {
    final source = Rect.fromLTWH(
      0,
      row * image.height / 5,
      image.width / 4,
      image.height / 5,
    );
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(FleetCardPainter old) =>
      old.image != image || old.row != row;
}

class BusCardPainter extends CustomPainter {
  const BusCardPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const source = Rect.fromLTWH(-74, -57, 148, 88);
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final scale = destination.width / source.width;
    canvas.save();
    canvas.translate(
      destination.left - source.left * scale,
      destination.top - source.top * scale,
    );
    canvas.scale(scale);
    ApronBus.draw(canvas, Offset.zero, -.28);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BusCardPainter oldDelegate) => false;
}

class TaskSpec {
  const TaskSpec(
    this.id,
    this.title,
    this.gate,
    this.duration, {
    this.after = const [],
    this.availableAt = 0,
    this.validFor = 0,
  });
  final String id, title;
  final int gate;
  final double duration, availableAt, validFor;
  final List<String> after;
}

class Mission {
  const Mission(
    this.id,
    this.title,
    this.location,
    this.brief, {
    this.seconds = 360,
    this.deadlines = const [290, 355],
    this.speed = 1,
    this.work = 1,
    this.tasks = const [],
    this.gusts = false,
  });
  final int id, location;
  final String title, brief;
  final double seconds, speed, work;
  final List<double> deadlines;
  final List<TaskSpec> tasks;
  final bool gusts;
  String get airport =>
      ['Night Hub', 'Azure Coast', 'Northern Airfield'][location];
  String get asset =>
      ['apron.png', 'scene-coast.png', 'scene-north.png'][location];
  String get weather => ['24° · CLEAR', '16° · WIND', '−12° · SNOW'][location];
  static const all = [
    Mission(
      0,
      'First Departure',
      0,
      'Learn to handle one aircraft, switch areas and queue ground services.',
      deadlines: [290],
    ),
    Mission(
      1,
      'Night Express',
      0,
      'A tighter schedule and one dispatch crew: balance inspections and baggage checks between flights.',
      seconds: 400,
      deadlines: [290, 380],
      tasks: [
        TaskSpec('inspect0', 'Aircraft inspection', 0, 12),
        TaskSpec('audit0', 'Baggage check', 0, 16, after: ['bags']),
        TaskSpec('inspect1', 'Aircraft inspection', 1, 12),
      ],
    ),
    Mission(
      2,
      'Sea Breeze',
      1,
      'Coastal winds slow vehicles. Every 90 seconds, stronger gusts last for 20 seconds. Secure equipment before boarding.',
      seconds: 840,
      deadlines: [450, 690, 815],
      speed: .88,
      gusts: true,
      tasks: [
        TaskSpec('secure0', 'Secure equipment', 0, 15),
        TaskSpec('secure1', 'Secure equipment', 1, 15),
        TaskSpec('secure2', 'Secure equipment', 2, 15),
      ],
    ),
    Mission(
      3,
      'Priority Flight',
      1,
      'The first flight must leave before the second. After one minute, an extra inspection of the second aircraft will be requested.',
      seconds: 810,
      deadlines: [360, 680, 790],
      speed: .88,
      gusts: true,
      tasks: [
        TaskSpec('vip0', 'VIP cabin preparation', 0, 20, after: ['clean']),
        TaskSpec('audit1', 'Baggage check', 1, 16, after: ['bags']),
        TaskSpec('inspect1', 'Extra inspection', 1, 18, availableAt: 60),
      ],
    ),
    Mission(
      4,
      'Cold Start',
      2,
      'De-ice each aircraft after boarding. Protection lasts 90 seconds: call the tug in time or repeat the treatment.',
      seconds: 550,
      deadlines: [430, 530],
      speed: .8,
      work: 1.1,
      tasks: [
        TaskSpec('deice0', 'De-icing', 0, 22, after: ['bus'], validFor: 90),
        TaskSpec('deice1', 'De-icing', 1, 22, after: ['bus'], validFor: 90),
      ],
    ),
    Mission(
      5,
      'Northern Rush',
      2,
      'Four aircraft across two aprons. Snow slows vehicles and servicing. Coordinate baggage checks, inspections and de-icing with just one crew.',
      seconds: 1450,
      deadlines: [520, 780, 1130, 1420],
      speed: .76,
      work: 1.15,
      gusts: true,
      tasks: [
        TaskSpec('audit0', 'Baggage check', 0, 18, after: ['bags']),
        TaskSpec('inspect1', 'Post-snow inspection', 1, 18, availableAt: 50),
        TaskSpec('deice0', 'De-icing', 0, 25, after: ['bus'], validFor: 90),
        TaskSpec('deice1', 'De-icing', 1, 25, after: ['bus'], validFor: 90),
        TaskSpec('deice2', 'De-icing', 2, 25, after: ['bus'], validFor: 90),
        TaskSpec('deice3', 'De-icing', 3, 25, after: ['bus'], validFor: 90),
      ],
    ),
  ];
}

class MissionTask {
  MissionTask(this.spec);
  final TaskSpec spec;
  double progress = 0;
  double? completedAt;
  bool active = false;
  bool get done => completedAt != null;
}

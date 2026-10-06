import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'game/player_profile.dart';
import 'game/missions.dart';
import 'game/shift.dart';
import 'l10n/strings.dart';

/// Store a small square PNG instead of a full-size personal photograph.
Future<Uint8List> prepareAvatar(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Image size');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      final longest = width > height ? width : height;
      final ratio = longest > 512 ? 512 / longest : 1.0;
      return ui.TargetImageSize(
        width: (width * ratio).round().clamp(1, 512),
        height: (height * ratio).round().clamp(1, 512),
      );
    },
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final side = image.width < image.height ? image.width : image.height;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          (image.width - side) / 2,
          (image.height - side) / 2,
          side.toDouble(),
          side.toDouble(),
        ),
        const Rect.fromLTWH(0, 0, 256, 256),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(256, 256);
      picture.dispose();
      try {
        final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const FormatException('Image decode');
        return data.buffer.asUint8List();
      } finally {
        cropped.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    this.bytes,
    this.radius = 22,
  });
  final String name;
  final Uint8List? bytes;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        name.trim().isEmpty ? '✈' : name.trim().characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * .8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    return ClipOval(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        color: const Color(0xff6545b9),
        child:
            bytes == null
                ? fallback
                : Image.memory(
                  bytes!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => fallback,
                ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profile, this.pickImage});
  final PlayerProfile profile;

  /// Injection point for exercising image import without a native picker in tests.
  final Future<Uint8List?> Function()? pickImage;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController name = TextEditingController(
    text: widget.profile.name,
  );
  late String language = widget.profile.language;
  late Uint8List? avatar = widget.profile.avatar;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> choosePhoto() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Uint8List? bytes;
      if (widget.pickImage != null) {
        bytes = await widget.pickImage!();
      } else {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          requestFullMetadata: false,
        );
        if (file != null) {
          if (await file.length() > 10 * 1024 * 1024) {
            throw const FormatException('Image size');
          }
          bytes = await file.readAsBytes();
        }
      }
      if (bytes != null) {
        final photo = await prepareAvatar(bytes);
        if (mounted) setState(() => avatar = photo);
      }
    } on PlatformException {
      if (mounted) {
        setState(
          () => error = 'Could not open the photo library. Please try again.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Choose a valid image up to 10 MB.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!PlayerProfile.validName(name.text)) {
      setState(() => error = 'Enter a name (1–24 characters).');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final ok = await widget.profile.save(
      name: name.text,
      language: language,
      avatar: avatar,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        busy = false;
        error = 'Could not save your profile. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    locale: Locale(language),
    child: Builder(
      builder: (context) {
        final tr = GameStrings.of(context).tr;
        return Dialog(
          backgroundColor: const Color(0xff141e39),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: LText(
                          'Profile',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Close'),
                        onPressed:
                            busy ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LText(
                          'Change your name, photo and language.',
                          style: TextStyle(color: Color(0xff95a3c6)),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            PlayerAvatar(
                              name: name.text,
                              bytes: avatar,
                              radius: 36,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextButton.icon(
                                    onPressed: busy ? null : choosePhoto,
                                    icon: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 18,
                                    ),
                                    label: const LText('Choose avatar'),
                                  ),
                                  if (avatar != null)
                                    TextButton(
                                      onPressed:
                                          busy
                                              ? null
                                              : () =>
                                                  setState(() => avatar = null),
                                      child: const LText('Remove photo'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const LText(
                          'PNG, JPG or WebP · up to 10 MB',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xff95a3c6),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          key: const Key('profile-name'),
                          controller: name,
                          maxLength: 24,
                          enabled: !busy,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: tr('Player name'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const LText(
                          'Language',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'en',
                                label: Text('English'),
                              ),
                              ButtonSegment(
                                value: 'de',
                                label: Text('Deutsch'),
                              ),
                            ],
                            selected: {language},
                            onSelectionChanged:
                                busy
                                    ? null
                                    : (v) =>
                                        setState(() => language = v.single),
                          ),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: LText(
                              error!,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: busy ? null : save,
                            child:
                                busy
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const LText('Save profile'),
                          ),
                        ),
                        const SizedBox(height: 26),
                        const Divider(),
                        const SizedBox(height: 12),
                        const LText(
                          'Shift history',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const LText(
                          'Stored on this device only. Latest 50 shifts.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xff95a3c6),
                          ),
                        ),
                        if (widget.profile.historySaveFailed)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LText(
                              'History could not be saved on this device.',
                              style: TextStyle(color: Colors.orangeAccent),
                            ),
                          ),
                        const SizedBox(height: 14),
                        if (widget.profile.history.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xff0c142b),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LText(
                                  'No shifts yet',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 6),
                                LText(
                                  'Finish a mission to see your results here.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xff95a3c6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        for (final record in widget.profile.history)
                          historyCard(record),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget historyCard(ShiftRecord r) {
    final date = r.finishedAt.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    final stamp =
        language == 'de'
            ? '${pad(date.day)}.${pad(date.month)}.${date.year}'
            : '${date.year}-${pad(date.month)}-${pad(date.day)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff0c142b),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            Mission.all[r.mission].title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '$stamp · ${pad(date.hour)}:${pad(date.minute)}',
            style: const TextStyle(fontSize: 11, color: Color(0xff95a3c6)),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(
              3,
              (i) => Icon(
                i < r.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                color: const Color(0xffffd28a),
                size: 18,
              ),
            ),
          ),
          const SizedBox(height: 6),
          LText(
            'Departed: ${r.departed}/${r.total} · On time: ${r.onTime}/${r.total}',
            style: const TextStyle(fontSize: 12),
          ),
          LText(
            'Credits: ${r.credits} · Duration: ${clockText(r.seconds.toDouble())}',
            style: const TextStyle(fontSize: 12, color: Color(0xff95a3c6)),
          ),
        ],
      ),
    );
  }
}

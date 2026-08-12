import '../json_utils.dart';
import 'figure.dart';

class PointKeyframe {
  /// Timeline position in FRAME indices (not seconds). Frame index is the
  /// stored unit; fps only affects playback speed.
  double time;
  double x;
  double y;

  PointKeyframe(this.time, this.x, this.y);

  Map<String, dynamic> toJson() => {'time': time, 'x': x, 'y': y};

  factory PointKeyframe.fromJson(Map<String, dynamic> json) => PointKeyframe(
        (json['time'] as num?)?.toDouble() ?? 0,
        (json['x'] as num?)?.toDouble() ?? 0,
        (json['y'] as num?)?.toDouble() ?? 0,
      );

  PointKeyframe clone() => PointKeyframe(time, x, y);
}

class PointTrack {
  int pointIndex;
  List<PointKeyframe> keyframes;

  PointTrack(this.pointIndex) : keyframes = [];

  void addKeyframe(double time, double x, double y) {
    final existing = keyframes
        .where((kf) => (kf.time - time).abs() < 0.001)
        .toList();
    if (existing.isNotEmpty) {
      existing.first.x = x;
      existing.first.y = y;
    } else {
      keyframes.add(PointKeyframe(time, x, y));
      keyframes.sort((a, b) => a.time.compareTo(b.time));
    }
  }

  bool removeKeyframe(double time) {
    final idx = keyframes
        .indexWhere((kf) => (kf.time - time).abs() < 0.001);
    if (idx != -1) {
      keyframes.removeAt(idx);
      return true;
    }
    return false;
  }

  PointKeyframe? getValue(double time, [bool easing = false]) {
    final keys = keyframes;
    if (keys.isEmpty) return null;
    if (keys.length == 1 || time <= keys.first.time) return keys.first;
    if (time >= keys.last.time) return keys.last;

    for (var i = 0; i < keys.length - 1; i++) {
      if (time >= keys[i].time && time < keys[i + 1].time) {
        final start = keys[i];
        final end = keys[i + 1];
        var t = (time - start.time) / (end.time - start.time);
        if (easing) {
          t = t * t * (3 - 2 * t);
        }
        return PointKeyframe(
          time,
          start.x + (end.x - start.x) * t,
          start.y + (end.y - start.y) * t,
        );
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'pointIndex': pointIndex,
        'keyframes': keyframes.map((kf) => kf.toJson()).toList(),
      };

  factory PointTrack.fromJson(Map<String, dynamic> data) {
    final track = PointTrack((data['pointIndex'] as num?)?.toInt() ?? 0);
    final raw = data['keyframes'];
    if (raw is List) {
      for (final kf in raw.whereType<Map<String, dynamic>>()) {
        track.addKeyframe(
          (kf['time'] as num?)?.toDouble() ?? 0,
          (kf['x'] as num?)?.toDouble() ?? 0,
          (kf['y'] as num?)?.toDouble() ?? 0,
        );
      }
    }
    return track;
  }

  PointTrack clone() => PointTrack.fromJson(toJson());
}

class FigureAnimation {
  String name;

  /// Number of frames in the timeline (>= 0). This is decoupled from [Figure.fps]:
  /// fps only controls playback speed, it never rescales keyframes, duration, or
  /// the total frame count.
  double duration;
  List<PointTrack> tracks;

  FigureAnimation([this.name = 'Animation'])
      : duration = 0,
        tracks = [];

  void addTrack(PointTrack track) => tracks.add(track);

  PointTrack? getTrack(int pointIndex) {
    for (final t in tracks) {
      if (t.pointIndex == pointIndex) return t;
    }
    return null;
  }

  PointTrack getOrCreateTrack(int pointIndex) {
    var track = getTrack(pointIndex);
    if (track == null) {
      track = PointTrack(pointIndex);
      tracks.add(track);
    }
    return track;
  }

  void setPointPose(double frame, int pointIndex, double x, double y) {
    final track = getOrCreateTrack(pointIndex);
    track.addKeyframe(frame, x, y);
    if (duration < frame + 1) duration = frame + 1;
  }

  bool removePointPose(double time, int pointIndex) {
    final track = getTrack(pointIndex);
    if (track == null) return false;
    final removed = track.removeKeyframe(time);
    if (track.keyframes.isEmpty) {
      tracks.removeWhere((t) => identical(t, track));
    }
    return removed;
  }

  void applyToFigure(Figure figure, double time, [bool easing = false]) {
    for (final track in tracks) {
      if (track.pointIndex < 0 || track.pointIndex >= figure.points.length) {
        continue;
      }
      final pt = figure.points[track.pointIndex];
      final val = track.getValue(time, easing);
      if (val != null) {
        pt.x = val.x;
        pt.y = val.y;
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'timeUnit': 'frame',
        'duration': duration,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  String exportToJson() => jsonEncodePretty(toJson());

  factory FigureAnimation.parse(
    Map<String, dynamic> data, {
    double? legacyFps,
  }) {
    final anim = FigureAnimation(data['name'] as String? ?? 'Animation');
    anim.duration = (data['duration'] as num?)?.toDouble() ?? 0;
    final raw = data['tracks'];
    if (raw is List) {
      for (final td in raw.whereType<Map<String, dynamic>>()) {
        anim.addTrack(PointTrack.fromJson(td));
      }
    }
    final isLegacy = data['timeUnit'] != 'frame';
    if (isLegacy && (legacyFps ?? 0) > 0) {
      for (final track in anim.tracks) {
        for (final kf in track.keyframes) {
          kf.time = kf.time * legacyFps!;
        }
      }
      anim.duration = anim.duration * legacyFps!;
    }
    return anim;
  }

  factory FigureAnimation.fromJsonString(String json,
          {double? legacyFps}) =>
      FigureAnimation.parse(jsonDecodeSafe(json), legacyFps: legacyFps);

  FigureAnimation clone() => FigureAnimation.parse(toJson());
}

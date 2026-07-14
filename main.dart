
import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const SensorCompassPro());

class SensorCompassPro extends StatefulWidget {
  const SensorCompassPro({super.key});

  @override
  State<SensorCompassPro> createState() => _SensorCompassProState();
}

class _SensorCompassProState extends State<SensorCompassPro> {
  ThemeMode themeMode = ThemeMode.dark;
  String language = 'mne';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      language = p.getString('language') ?? 'mne';
      final value = p.getString('theme') ?? 'dark';
      themeMode = value == 'light'
          ? ThemeMode.light
          : value == 'system'
              ? ThemeMode.system
              : ThemeMode.dark;
    });
  }

  Future<void> setLanguage(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('language', value);
    setState(() => language = value);
  }

  Future<void> setTheme(ThemeMode value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', value.name);
    setState(() => themeMode = value);
  }

  @override
  Widget build(BuildContext context) {
    const darkBg = Color(0xFF050B11);
    const darkSurface = Color(0xFF0B141D);
    const cyan = Color(0xFF15B8F4);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sensor Compass Pro',
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: cyan,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: darkBg,
        cardTheme: const CardThemeData(
          color: darkSurface,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        dividerColor: Colors.white12,
        colorScheme: ColorScheme.fromSeed(
          seedColor: cyan,
          brightness: Brightness.dark,
          surface: darkSurface,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF08111A),
          indicatorColor: Color(0xFF12374A),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11),
          ),
        ),
      ),
      home: HomeScreen(
        language: language,
        themeMode: themeMode,
        onLanguage: setLanguage,
        onTheme: setTheme,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.language,
    required this.themeMode,
    required this.onLanguage,
    required this.onTheme,
  });

  final String language;
  final ThemeMode themeMode;
  final ValueChanged<String> onLanguage;
  final ValueChanged<ThemeMode> onTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class PressureSample {
  const PressureSample(this.time, this.value);
  final DateTime time;
  final double value;
}

class _HomeScreenState extends State<HomeScreen> {
  int page = 0;
  double? heading;
  double? compassAccuracy;
  double? pressure;
  double? latitude;
  double? longitude;
  double? altitude;
  double? gpsAccuracy;
  double? speed;
  double seaLevelPressure = 1013.25;

  bool compassAvailable = false;
  bool barometerAvailable = false;
  bool accelerometerAvailable = false;
  bool gyroAvailable = false;
  bool gpsAvailable = false;
  bool keepScreenOn = false;
  bool autoCalibration = true;

  String? gpsMessage;

  StreamSubscription<CompassEvent>? compassSub;
  StreamSubscription<BarometerEvent>? barometerSub;
  StreamSubscription<AccelerometerEvent>? accelerometerSub;
  StreamSubscription<GyroscopeEvent>? gyroSub;
  StreamSubscription<Position>? positionSub;

  final List<PressureSample> samples = [];

  bool get mne => widget.language == 'mne';
  String tr(String mneText, String engText) => mne ? mneText : engText;

  @override
  void initState() {
    super.initState();
    startSensors();
  }

  Future<void> startSensors() async {
    compassSub?.cancel();
    compassSub = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() {
        heading = event.heading;
        compassAccuracy = event.accuracy;
        compassAvailable = event.heading != null;
      });
    });

    try {
      barometerSub?.cancel();
      barometerSub = barometerEventStream(
        samplingPeriod: const Duration(seconds: 2),
      ).listen((event) {
        if (!mounted) return;
        setState(() {
          pressure = event.pressure;
          barometerAvailable = true;
          samples.add(PressureSample(DateTime.now(), event.pressure));
          if (samples.length > 120) samples.removeAt(0);
        });
      }, onError: (_) {
        if (mounted) setState(() => barometerAvailable = false);
      });
    } catch (_) {
      barometerAvailable = false;
    }

    accelerometerSub?.cancel();
    accelerometerSub = accelerometerEventStream(
      samplingPeriod: const Duration(seconds: 1),
    ).listen((_) {
      if (mounted && !accelerometerAvailable) {
        setState(() => accelerometerAvailable = true);
      }
    });

    gyroSub?.cancel();
    gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(seconds: 1),
    ).listen((_) {
      if (mounted && !gyroAvailable) {
        setState(() => gyroAvailable = true);
      }
    });

    await startGps();
  }

  Future<void> startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => gpsMessage = tr(
              'Uključi lokaciju za GPS podatke.',
              'Enable location for GPS data.',
            ));
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => gpsMessage = tr(
              'Dozvola za lokaciju nije odobrena.',
              'Location permission was not granted.',
            ));
        return;
      }

      positionSub?.cancel();
      positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 1,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() {
          gpsAvailable = true;
          latitude = p.latitude;
          longitude = p.longitude;
          altitude = p.altitude;
          gpsAccuracy = p.accuracy;
          speed = math.max(0, p.speed * 3.6);
          gpsMessage = null;
        });
      });
    } catch (_) {
      setState(() => gpsMessage = tr(
            'GPS trenutno nije dostupan.',
            'GPS is currently unavailable.',
          ));
    }
  }

  double? get baroAltitude {
    final p = pressure;
    if (p == null || p <= 0) return null;
    return 44330 *
        (1 - math.pow(p / seaLevelPressure, 0.190294957).toDouble());
  }

  String direction(double? value) {
    if (value == null) return '--';
    const mneDirections = ['S', 'SI', 'I', 'JI', 'J', 'JZ', 'Z', 'SZ'];
    const engDirections = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final list = mne ? mneDirections : engDirections;
    return list[((value + 22.5) ~/ 45) % 8];
  }

  String directionName(double? value) {
    if (value == null) return tr('Nedostupno', 'Unavailable');
    const mneNames = [
      'Sjever',
      'Sjeveroistok',
      'Istok',
      'Jugoistok',
      'Jug',
      'Jugozapad',
      'Zapad',
      'Sjeverozapad',
    ];
    const engNames = [
      'North',
      'North-East',
      'East',
      'South-East',
      'South',
      'South-West',
      'West',
      'North-West',
    ];
    return (mne ? mneNames : engNames)[((value + 22.5) ~/ 45) % 8];
  }

  Future<void> calibrateAltimeter() async {
    if (pressure == null || altitude == null) return;
    final ratio = 1 - altitude! / 44330;
    final result = pressure! / math.pow(ratio, 1 / 0.190294957);
    setState(() => seaLevelPressure = result.toDouble());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(
          'Altimetar je kalibrisan prema GPS visini.',
          'Altimeter calibrated using GPS altitude.',
        )),
      ),
    );
  }

  String pressureTrend() {
    if (samples.length < 8) return tr('Prikupljanje podataka', 'Collecting data');
    final delta = samples.last.value - samples[samples.length - 8].value;
    if (delta > 0.5) return tr('Raste', 'Rising');
    if (delta < -0.5) return tr('Opada', 'Falling');
    return tr('Stabilan', 'Steady');
  }

  String localForecast() {
    if (samples.length < 8) {
      return tr('Sačekaj više mjerenja.', 'Wait for more measurements.');
    }
    final delta = samples.last.value - samples[samples.length - 8].value;
    if (delta < -1) {
      return tr(
        'Moguća promjena vremena ili padavine.',
        'Possible weather change or precipitation.',
      );
    }
    if (delta > 1) {
      return tr(
        'Vjerovatno stabilnije vrijeme.',
        'Likely more stable weather.',
      );
    }
    return tr(
      'Nema značajne promjene pritiska.',
      'No significant pressure change.',
    );
  }

  @override
  void dispose() {
    compassSub?.cancel();
    barometerSub?.cancel();
    accelerometerSub?.cancel();
    gyroSub?.cancel();
    positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      compassScreen(),
      barometerScreen(),
      locationScreen(),
      sensorsScreen(),
      settingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text([
          tr('Kompas', 'Compass'),
          tr('Barometar', 'Barometer'),
          tr('Lokacija', 'Location'),
          tr('Senzori', 'Sensors'),
          tr('Podešavanja', 'Settings'),
        ][page]),
        centerTitle: true,
        actions: [
          if (page == 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: const Icon(Icons.cloud_off, size: 17),
                label: Text(tr('OFFLINE', 'OFFLINE')),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      body: SafeArea(child: screens[page]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (value) => setState(() => page = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: tr('Kompas', 'Compass'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.speed_outlined),
            selectedIcon: const Icon(Icons.speed),
            label: tr('Pritisak', 'Pressure'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.location_on_outlined),
            selectedIcon: const Icon(Icons.location_on),
            label: 'GPS',
          ),
          NavigationDestination(
            icon: const Icon(Icons.sensors_outlined),
            selectedIcon: const Icon(Icons.sensors),
            label: tr('Senzori', 'Sensors'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: tr('Postavke', 'Settings'),
          ),
        ],
      ),
    );
  }

  Widget compassScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: smallStatus(
                tr('Magnetno polje', 'Magnetic field'),
                compassAccuracy == null
                    ? '--'
                    : '${compassAccuracy!.abs().toStringAsFixed(0)} μT',
                compassAvailable,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: smallStatus(
                tr('Tačnost', 'Accuracy'),
                compassAvailable ? tr('Visoka', 'High') : '--',
                compassAvailable,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
          decoration: panelDecoration(),
          child: Column(
            children: [
              SizedBox(
                height: 330,
                child: CustomPaint(
                  painter: PremiumCompassPainter(
                    heading ?? 0,
                    Theme.of(context).colorScheme,
                  ),
                ),
              ),
              Text(
                heading == null
                    ? '--°'
                    : '${heading!.round()}° ${direction(heading)}',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                directionName(heading),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: metricCard(
                tr('BAROMETAR', 'BAROMETER'),
                pressure,
                'hPa',
                1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: metricCard(
                tr('VISINA BARO', 'BARO ALTITUDE'),
                baroAltitude,
                'm',
                0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: metricCard(
                tr('GPS VISINA', 'GPS ALTITUDE'),
                altitude,
                'm',
                0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: metricCard(
                tr('BRZINA', 'SPEED'),
                speed,
                'km/h',
                1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: metricCard(
                tr('GPS TAČNOST', 'GPS ACCURACY'),
                gpsAccuracy,
                'm',
                0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: panelDecoration(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.eco, color: Colors.lightGreenAccent),
              const SizedBox(width: 8),
              Text(
                tr(
                  'OFFLINE MOD – internet nije potreban',
                  'OFFLINE MODE – no internet required',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget barometerScreen() {
    final chartSamples = samples.isEmpty
        ? [const PressureSample(nullTime, 1013.25)]
        : samples;
    final values = chartSamples.map((e) => e.value).toList();
    final minY = values.reduce(math.min) - 1.2;
    final maxY = values.reduce(math.max) + 1.2;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: panelDecoration(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Vazdušni pritisak', 'Air pressure')),
                    const SizedBox(height: 3),
                    Text(
                      pressure == null
                          ? '-- hPa'
                          : '${pressure!.toStringAsFixed(1)} hPa',
                      style: const TextStyle(
                        fontSize: 35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      tr('Standardni pritisak', 'Standard pressure'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(tr('Trend', 'Trend')),
                  Text(
                    pressureTrend(),
                    style: const TextStyle(
                      color: Colors.lightGreenAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
          decoration: panelDecoration(),
          child: Column(
            children: [
              Text(
                tr('PRITISAK (hPa) – POSLJEDNJA MJERENJA',
                    'PRESSURE (hPa) – RECENT READINGS'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 260,
                child: LineChart(
                  LineChartData(
                    minY: minY,
                    maxY: maxY,
                    gridData: FlGridData(
                      getDrawingHorizontalLine: (_) =>
                          const FlLine(color: Colors.white10, strokeWidth: 1),
                      getDrawingVerticalLine: (_) =>
                          const FlLine(color: Colors.white10, strokeWidth: 1),
                    ),
                    titlesData: const FlTitlesData(
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: Colors.white12),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (int i = 0; i < chartSamples.length; i++)
                            FlSpot(i.toDouble(), chartSamples[i].value),
                        ],
                        isCurved: true,
                        barWidth: 3,
                        color: Colors.lightGreenAccent,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.lightGreenAccent.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: statBox('MIN', values.reduce(math.min))),
            const SizedBox(width: 8),
            Expanded(child: statBox('MAX', values.reduce(math.max))),
            const SizedBox(width: 8),
            Expanded(
              child: statBox(
                tr('PROSJEK', 'AVG'),
                values.reduce((a, b) => a + b) / values.length,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: panelDecoration(),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              child: Icon(Icons.cloud_queue),
            ),
            title: Text(tr('Lokalna prognoza', 'Local forecast')),
            subtitle: Text(localForecast()),
            trailing: const Icon(Icons.offline_bolt),
          ),
        ),
      ],
    );
  }

  Widget locationScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 290,
          decoration: panelDecoration(),
          child: CustomPaint(
            painter: OfflineMapPainter(
              latitude: latitude,
              longitude: longitude,
              colorScheme: Theme.of(context).colorScheme,
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (gpsMessage != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: panelDecoration(),
            child: Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 10),
                Expanded(child: Text(gpsMessage!)),
                IconButton(
                  onPressed: startGps,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: coordinateCard(
                tr('GEOGRAFSKA ŠIRINA', 'LATITUDE'),
                latitude,
                '°',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: coordinateCard(
                tr('GEOGRAFSKA DUŽINA', 'LONGITUDE'),
                longitude,
                '°',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: metricCard(
                tr('GPS VISINA', 'GPS ALTITUDE'),
                altitude,
                'm',
                0,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: metricCard(
                tr('TAČNOST', 'ACCURACY'),
                gpsAccuracy,
                'm',
                0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: panelDecoration(),
          child: Text(
            tr(
              'Offline prikaz ne preuzima internet mapu. Prikazuje položaj, koordinate, visinu i tačnost direktno iz GPS senzora.',
              'The offline view does not download an internet map. It shows position, coordinates, altitude and accuracy directly from GPS.',
            ),
          ),
        ),
      ],
    );
  }

  Widget sensorsScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        sensorRow(
          Icons.motion_photos_auto,
          tr('Akcelerometar', 'Accelerometer'),
          accelerometerAvailable,
        ),
        sensorRow(
          Icons.explore,
          tr('Magnetometar', 'Magnetometer'),
          compassAvailable,
        ),
        sensorRow(
          Icons.speed,
          tr('Barometar', 'Barometer'),
          barometerAvailable,
        ),
        sensorRow(
          Icons.threed_rotation,
          tr('Žiroskop', 'Gyroscope'),
          gyroAvailable,
        ),
        sensorRow(Icons.gps_fixed, 'GPS', gpsAvailable),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: panelDecoration(),
          child: Column(
            children: [
              const Icon(Icons.all_inclusive, size: 48),
              const SizedBox(height: 10),
              Text(
                tr(
                  'Kalibracija kompasa',
                  'Compass calibration',
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Pomjeraj telefon nekoliko puta u obliku broja 8, dalje od magneta i metala.',
                  'Move the phone several times in a figure-eight pattern, away from magnets and metal.',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed:
              pressure != null && altitude != null ? calibrateAltimeter : null,
          icon: const Icon(Icons.tune),
          label: Text(tr(
            'Kalibriši altimetar prema GPS-u',
            'Calibrate altimeter using GPS',
          )),
        ),
      ],
    );
  }

  Widget settingsScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        sectionTitle(tr('IZGLED', 'APPEARANCE')),
        settingsTile(
          Icons.dark_mode,
          tr('Tema', 'Theme'),
          widget.themeMode == ThemeMode.dark
              ? tr('Tamna', 'Dark')
              : widget.themeMode == ThemeMode.light
                  ? tr('Svijetla', 'Light')
                  : tr('Sistemska', 'System'),
          onTap: showThemeDialog,
        ),
        settingsTile(
          Icons.language,
          tr('Jezik', 'Language'),
          widget.language == 'mne' ? 'MNE' : 'ENG',
          onTap: showLanguageDialog,
        ),
        settingsTile(
          Icons.straighten,
          tr('Jedinice', 'Units'),
          tr('Metrički sistem', 'Metric system'),
        ),
        const SizedBox(height: 18),
        sectionTitle(tr('OPŠTE', 'GENERAL')),
        switchTile(
          Icons.auto_fix_high,
          tr('Automatska kalibracija', 'Auto calibration'),
          autoCalibration,
          (value) => setState(() => autoCalibration = value),
        ),
        switchTile(
          Icons.screen_lock_portrait,
          tr('Ekran stalno uključen', 'Keep screen on'),
          keepScreenOn,
          (value) => setState(() => keepScreenOn = value),
        ),
        settingsTile(
          Icons.cloud_off,
          tr('Offline mod', 'Offline mode'),
          tr('Uvijek aktivan', 'Always active'),
        ),
        const SizedBox(height: 18),
        sectionTitle(tr('O APLIKACIJI', 'ABOUT')),
        const AboutListTile(
          icon: Icon(Icons.explore),
          applicationIcon: Icon(Icons.explore, size: 42),
          applicationName: 'Sensor Compass Pro',
          applicationVersion: '3.0.0',
          applicationLegalese: 'MS Tech',
        ),
      ],
    );
  }

  BoxDecoration panelDecoration() {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white12),
      boxShadow: const [
        BoxShadow(
          blurRadius: 20,
          color: Colors.black26,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  Widget smallStatus(String title, String value, bool active) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: active ? Colors.lightGreenAccent : Colors.white54,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget metricCard(
    String title,
    double? value,
    String unit,
    int decimals,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: panelDecoration(),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Colors.white60),
          ),
          const SizedBox(height: 5),
          FittedBox(
            child: Text(
              value == null ? '--' : value.toStringAsFixed(decimals),
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(unit, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget coordinateCard(String title, double? value, String unit) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: panelDecoration(),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 10)),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(
              value == null ? '--' : '${value.toStringAsFixed(6)}$unit',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget statBox(String title, double value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: panelDecoration(),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 10)),
          const SizedBox(height: 5),
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Text('hPa', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget sensorRow(IconData icon, String title, bool active) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: panelDecoration(),
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              active ? tr('Aktivan', 'Active') : tr('Nedostupan', 'Unavailable'),
              style: TextStyle(
                color: active ? Colors.lightGreenAccent : Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              active ? Icons.circle : Icons.error_outline,
              size: 10,
              color: active ? Colors.lightGreenAccent : Colors.redAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white54,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget settingsTile(
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: panelDecoration(),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget switchTile(
    IconData icon,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: panelDecoration(),
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Future<void> showLanguageDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Izaberi jezik', 'Choose language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              value: 'mne',
              groupValue: widget.language,
              title: const Text('🇲🇪 Crnogorski (MNE)'),
              onChanged: (value) {
                if (value != null) widget.onLanguage(value);
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              value: 'eng',
              groupValue: widget.language,
              title: const Text('🇬🇧 English (ENG)'),
              onChanged: (value) {
                if (value != null) widget.onLanguage(value);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showThemeDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Izaberi temu', 'Choose theme')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(
                value: mode,
                groupValue: widget.themeMode,
                title: Text(
                  mode == ThemeMode.dark
                      ? tr('Tamna', 'Dark')
                      : mode == ThemeMode.light
                          ? tr('Svijetla', 'Light')
                          : tr('Sistemska', 'System'),
                ),
                onChanged: (value) {
                  if (value != null) widget.onTheme(value);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

const DateTime nullTime = DateTime.fromMillisecondsSinceEpoch(0);

class PremiumCompassPainter extends CustomPainter {
  PremiumCompassPainter(this.heading, this.scheme);

  final double heading;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF152430), Color(0xFF02070B)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = scheme.primary,
    );

    canvas.drawCircle(
      center,
      radius - 20,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white24,
    );

    for (int i = 0; i < 72; i++) {
      final angle = i * 5 * math.pi / 180;
      final major = i % 6 == 0;
      final start = radius - (major ? 22 : 10);
      final p1 = Offset(
        center.dx + math.sin(angle) * start,
        center.dy - math.cos(angle) * start,
      );
      final p2 = Offset(
        center.dx + math.sin(angle) * (radius - 2),
        center.dy - math.cos(angle) * (radius - 2),
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..strokeWidth = major ? 2.5 : 1
          ..color = major ? Colors.white : Colors.white38,
      );
    }

    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final position = Offset(
        center.dx + math.sin(angle) * (radius - 49),
        center.dy - math.cos(angle) * (radius - 49),
      );
      final painter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: i == 0
                ? Colors.redAccent
                : i == 4
                    ? Colors.lightBlueAccent
                    : Colors.white,
            fontSize: i.isEven ? 21 : 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180);

    final north = Path()
      ..moveTo(0, -radius * .68)
      ..lineTo(-27, 18)
      ..lineTo(0, 2)
      ..lineTo(27, 18)
      ..close();
    canvas.drawPath(
      north,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.red, Color(0xFF7A0000)],
        ).createShader(Rect.fromLTRB(-30, -radius, 30, 20)),
    );

    final south = Path()
      ..moveTo(0, radius * .68)
      ..lineTo(-27, -18)
      ..lineTo(0, -2)
      ..lineTo(27, -18)
      ..close();
    canvas.drawPath(
      south,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.lightBlueAccent, Color(0xFF004B78)],
        ).createShader(Rect.fromLTRB(-30, -20, 30, radius)),
    );

    canvas.restore();

    canvas.drawCircle(center, 19, Paint()..color = Colors.white70);
    canvas.drawCircle(center, 11, Paint()..color = Colors.black87);
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant PremiumCompassPainter oldDelegate) {
    return oldDelegate.heading != heading || oldDelegate.scheme != scheme;
  }
}

class OfflineMapPainter extends CustomPainter {
  OfflineMapPainter({
    required this.latitude,
    required this.longitude,
    required this.colorScheme,
  });

  final double? latitude;
  final double? longitude;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      bg,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFF172A28),
            Color(0xFF243328),
            Color(0xFF131F21),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bg),
    );

    final roadPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final minorRoadPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < 8; i++) {
      final y = size.height * (i + 1) / 9;
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 20), minorRoadPaint);
    }
    for (int i = 0; i < 7; i++) {
      final x = size.width * (i + 1) / 8;
      canvas.drawLine(Offset(x, 0), Offset(x + 25, size.height), minorRoadPaint);
    }

    final river = Path()
      ..moveTo(0, size.height * .76)
      ..cubicTo(
        size.width * .25,
        size.height * .48,
        size.width * .55,
        size.height * .92,
        size.width,
        size.height * .38,
      );
    canvas.drawPath(
      river,
      Paint()
        ..color = Colors.lightBlueAccent.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    final route = Path()
      ..moveTo(size.width * .08, size.height * .2)
      ..cubicTo(
        size.width * .25,
        size.height * .4,
        size.width * .6,
        size.height * .1,
        size.width * .92,
        size.height * .75,
      );
    canvas.drawPath(route, roadPaint);

    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      18,
      Paint()..color = Colors.blueAccent.withValues(alpha: .25),
    );
    canvas.drawCircle(center, 9, Paint()..color = Colors.blueAccent);
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );

    final text = latitude == null
        ? 'GPS'
        : '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(12, size.height - tp.height - 12));
  }

  @override
  bool shouldRepaint(covariant OfflineMapPainter oldDelegate) {
    return oldDelegate.latitude != latitude ||
        oldDelegate.longitude != longitude ||
        oldDelegate.colorScheme != colorScheme;
  }
}

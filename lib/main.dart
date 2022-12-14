import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:udp/udp.dart';
import 'ffi.dart' if (dart.library.html) 'ffi_web.dart';
import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'fk-app.pb.dart' as app;
import 'package:protobuf/protobuf.dart' as protobuf;
import 'package:provider/provider.dart';

class Station {
  final String deviceId;
  final String name;

  const Station({
    required this.deviceId,
    required this.name,
  });
}

class KnownStationsModel extends ChangeNotifier {
  final List<Station> _stations = [
    const Station(deviceId: '0', name: 'Quirky Puppy 34'),
    const Station(deviceId: '1', name: 'Super Slinky 11'),
    const Station(deviceId: '2', name: 'Slippery Penguin 20'),
  ];

  UnmodifiableListView<Station> get stations => UnmodifiableListView(_stations);

  void add(Station station) {
    _stations.add(station);
    notifyListeners();
  }
}

Future<app.HttpReply> fetchStatus(address) async {
  var response = await http.get(Uri.parse("http://${address.address}/fk/v1"));
  var reader = protobuf.CodedBufferReader(response.bodyBytes);
  var bytes = reader.readBytes();
  return app.HttpReply.fromBuffer(bytes);
}

void main() async {
  var multicastEndpoint = Endpoint.multicast(InternetAddress("224.0.0.123"),
      port: const Port(22143));
  var receiver = await UDP.bind(multicastEndpoint);

  receiver.asStream().listen((datagram) async {
    developer.log("udp:packet ${datagram?.address} ${datagram?.data}");

    if (datagram != null) {
      var status = await fetchStatus(datagram.address);
      developer.log("ok $status");
    }
  });

  // todo: Close receiver

  runApp(ChangeNotifierProvider(
    create: (context) => KnownStationsModel(),
    child: const OurApp(),
  ));
}

class StationsTab extends StatelessWidget {
  const StationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(onGenerateRoute: (RouteSettings settings) {
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => Consumer<KnownStationsModel>(
          builder: (context, knownStations, child) {
            return ListStationsRoute(stations: knownStations.stations);
          },
        ),
      );
    });
  }
}

class DataSyncTab extends StatelessWidget {
  const DataSyncTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(onGenerateRoute: (RouteSettings settings) {
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => const DataSyncRoute(),
      );
    });
  }
}

class Map extends StatelessWidget {
  const Map({super.key});

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        center: LatLng(48.864716, 2.349014),
        zoom: 9.2,
      ),
      nonRotatedChildren: [
        AttributionWidget.defaultWidget(
          source: 'OpenStreetMap contributors',
          onSourceTapped: null,
        ),
      ],
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app',
        ),
      ],
    );
  }
}

class ListStationsRoute extends StatelessWidget {
  const ListStationsRoute({super.key, required this.stations});

  final List<Station> stations;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Stations'),
      ),
      body: ListView.builder(
        itemCount: stations.length + 1,
        itemBuilder: (context, index) {
          // This is a huge hack, but was the fastest way to get this working
          // and shouldn't leak outside of this class.
          if (index == 0) {
            return const SizedBox(height: 300, child: Map());
          }

          return ListTile(
            title: Text(stations[index - 1].name),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ViewStationRoute(station: stations[index - 1]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ViewStationRoute extends StatelessWidget {
  const ViewStationRoute({super.key, required this.station});

  final Station station;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(station.name),
      ),
      body: Center(
        child: ElevatedButton(
          child: const Text('Back'),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

class DataSyncRoute extends StatelessWidget {
  const DataSyncRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Sync'),
      ),
      body: const Center(),
    );
  }
}

class OurApp extends StatefulWidget {
  const OurApp({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _OurAppState();
  }
}

class _OurAppState extends State<OurApp> {
  Timer? timer;

  @override
  void initState() {
    developer.log("app-state:initialize");
    super.initState();

    timer = Timer(
      const Duration(seconds: 3),
      () {
        developer.log("app-state:tick");
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
    timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldKit',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // These futures belong to the state and are only initialized once,
  // in the initState method.
  late Future<Platform> platform;
  late Future<bool> isRelease;

  @override
  void initState() {
    super.initState();
    platform = api.platform();
    isRelease = api.rustReleaseMode();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text("You're running on"),
            // To render the results of a Future, a FutureBuilder is used which
            // turns a Future into an AsyncSnapshot, which can be used to
            // extract the error state, the loading state and the data if
            // available.
            //
            // Here, the generic type that the FutureBuilder manages is
            // explicitly named, because if omitted the snapshot will have the
            // type of AsyncSnapshot<Object?>.
            FutureBuilder<List<dynamic>>(
              // We await two unrelated futures here, so the type has to be
              // List<dynamic>.
              future: Future.wait([platform, isRelease]),
              builder: (context, snap) {
                final style = Theme.of(context).textTheme.headline4;
                if (snap.error != null) {
                  // An error has been encountered, so give an appropriate response and
                  // pass the error details to an unobstructive tooltip.
                  debugPrint(snap.error.toString());
                  return Tooltip(
                    message: snap.error.toString(),
                    child: Text('Unknown OS', style: style),
                  );
                }

                // Guard return here, the data is not ready yet.
                final data = snap.data;
                if (data == null) return const CircularProgressIndicator();

                // Finally, retrieve the data expected in the same order provided
                // to the FutureBuilder.future.
                final Platform platform = data[0];
                final release = data[1] ? 'Release' : 'Debug';
                final text = const {
                      Platform.Android: 'Android',
                      Platform.Ios: 'iOS',
                      Platform.MacApple: 'MacOS with Apple Silicon',
                      Platform.MacIntel: 'MacOS',
                      Platform.Windows: 'Windows',
                      Platform.Unix: 'Unix',
                      Platform.Wasm: 'the Web',
                    }[platform] ??
                    'Unknown OS';
                return Text('$text ($release)', style: style);
              },
            )
          ],
        ),
      ),
    );
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(onGenerateRoute: (RouteSettings settings) {
      return MaterialPageRoute(
          settings: settings,
          builder: (BuildContext context) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Settings'),
              ),
              body: Center(
                child: ElevatedButton(
                  child: const Text('Settings'),
                  onPressed: () {},
                ),
              ),
            );
          });
    });
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _pageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _pageIndex,
          children: const <Widget>[
            StationsTab(),
            DataSyncTab(),
            SettingsTab(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Stations',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.business),
            label: 'Data',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.computer),
            label: 'Settings',
          ),
        ],
        currentIndex: _pageIndex,
        onTap: (int index) {
          setState(
            () {
              _pageIndex = index;
            },
          );
        },
      ),
    );
  }
}

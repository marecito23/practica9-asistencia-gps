import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

const String baseUrl = "http://localhost:8000";

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pase de Lista GPS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// --- PANTALLA 1: LOGIN Y REGISTRO ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = "student";
  bool _isRegisterMode = false;
  bool _isLoading = false;

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showSnack("Completa usuario y contraseña");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final endpoint = _isRegisterMode ? "/register/" : "/login/";
      final body = _isRegisterMode
          ? {"username": username, "password": password, "role": _selectedRole}
          : {"username": username, "password": password};

      final response = await http.post(
        Uri.parse("$baseUrl$endpoint"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        if (_isRegisterMode) {
          _showSnack("Usuario registrado. Ahora inicia sesión.");
          setState(() => _isRegisterMode = false);
        } else {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => HomeScreen(
                userId: data["user_id"],
                username: data["username"],
                role: data["role"],
              ),
            ),
          );
        }
      } else {
        _showSnack(data["detail"] ?? "Error en la solicitud");
      }
    } catch (e) {
      _showSnack("No se pudo conectar al servidor: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isRegisterMode ? "Registro de Usuario" : "Iniciar Sesión")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, size: 72, color: Colors.indigo),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: "Usuario",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Contraseña",
                border: OutlineInputBorder(),
              ),
            ),
            if (_isRegisterMode) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(
                  labelText: "Rol",
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: "student", child: Text("Alumno (student)")),
                  DropdownMenuItem(value: "admin", child: Text("Administrador (admin)")),
                ],
                onChanged: (val) => setState(() => _selectedRole = val ?? "student"),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(_isRegisterMode ? "Registrarse" : "Entrar"),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _isRegisterMode = !_isRegisterMode),
              child: Text(
                _isRegisterMode
                    ? "¿Ya tienes cuenta? Inicia sesión"
                    : "¿No tienes cuenta? Regístrate aquí",
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- PANTALLA 2: PASE DE LISTA Y HISTORIAL ---
class HomeScreen extends StatefulWidget {
  final int userId;
  final String username;
  final String role;

  const HomeScreen({
    super.key,
    required this.userId,
    required this.username,
    required this.role,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSending = false;
  String _lastResult = "Presiona el botón para registrar tu asistencia con GPS.";
  List<dynamic> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception("El GPS del dispositivo está desactivado.");
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception("Permiso de ubicación denegado.");
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception("Permisos de ubicación bloqueados permanentemente.");
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _registerAttendance() async {
    setState(() => _isSending = true);

    try {
      final pos = await _determinePosition();

      final response = await http.post(
        Uri.parse("$baseUrl/attendance/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.userId,
          "latitude": pos.latitude,
          "longitude": pos.longitude,
        }),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        setState(() {
          _lastResult =
              "Asistencia registrada\nLat: ${data['latitude']}\nLon: ${data['longitude']}\nDirección: ${data['address']}";
        });
        await _loadHistory();
      } else {
        setState(() => _lastResult = "Error: ${data['detail']}");
      }
    } catch (e) {
      setState(() => _lastResult = "Error al obtener GPS o enviar datos: $e");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final url = widget.role == "admin"
          ? "$baseUrl/attendance/"
          : "$baseUrl/attendance/?user_id=${widget.userId}";

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        setState(() {
          _history = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Hola, ${widget.username} (${widget.role})"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.my_location),
                label: Text(_isSending ? "Obteniendo ubicación..." : "Registrar Asistencia GPS"),
                onPressed: _isSending ? null : _registerAttendance,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(_lastResult),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Historial de Asistencias",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _history.isEmpty
                  ? const Center(child: Text("Aún no hay registros."))
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.check_circle, color: Colors.green),
                            title: Text("${item['username']} - ${item['created_at']}"),
                            subtitle: Text(
                              "${item['address']}\n(${item['latitude']}, ${item['longitude']})",
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
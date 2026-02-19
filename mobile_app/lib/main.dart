import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; 

import 'agency_dashboard.dart';
import 'admin_dashboard.dart'; 
import 'driver_dashboard.dart';

void main() {
  // const String myComputerIp = "192.168.1.5";
  String smartUrl = kIsWeb 
      ? "http://localhost:8000/login"   // Browser
      // : "http://$myComputerIp:8000/login";
      : "http://10.0.2.2:8000/login";  // Mobile Emulator


  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: LoginScreen(serverUrl: smartUrl),
  ));
}

// 1. LOGIN SCREEN
class LoginScreen extends StatefulWidget {
  final String serverUrl;
  const LoginScreen({super.key, required this.serverUrl});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controllers
  final TextEditingController _emailController = TextEditingController(); 
  final TextEditingController _passwordController = TextEditingController();
  
  // Driver Specific Controllers
  final TextEditingController _agencyEmailController = TextEditingController(); 
  final TextEditingController _vanNumberController = TextEditingController();

  String _selectedRole = 'Agency'; 
  String _errorMessage = "";
  bool _isLoading = false;

  Future<void> _login() async {
    final baseUrl = widget.serverUrl.replaceAll('/login', '');
    setState(() {
       _errorMessage = "";
       _isLoading = true;
    });

    try {
      http.Response response;
      
      if (_selectedRole == 'Driver') {
        // DRIVER LOGIN 
        response = await http.post(
          Uri.parse("$baseUrl/login/driver"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "agency_email": _agencyEmailController.text,
            "van_number": _vanNumberController.text,
            "password": _passwordController.text,
          }),
        ).timeout(const Duration(seconds: 5));
      } else {
        // ADMIN/AGENCY LOGIN 
        response = await http.post(
          Uri.parse("$baseUrl/login"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "email": _emailController.text,
            "password": _passwordController.text,
            "role": _selectedRole.toLowerCase(), 
          }),
        ).timeout(const Duration(seconds: 5));
      }

      if (response.statusCode == 200) {
        final user = jsonDecode(response.body);
        if (!mounted) return;

        if (user['status'] == 'pending') {
          setState(() => _errorMessage = "Account Pending Admin Approval");
          return;
        }

        // NAVIGATION 
        if (user['role'] == 'driver') {
           Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => DriverDashboard(
              serverUrl: widget.serverUrl, 
              driverId: user['id'],
              driverName: user['name']
            )));
        } else if (user['role'] == 'agency') {
           Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => AgencyDashboard(serverUrl: widget.serverUrl, agencyId: user['id'])
          ));
        } else if (user['role'] == 'admin') {
           Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => AdminDashboard(serverUrl: widget.serverUrl)
          ));
        }
      } else {
        final error = jsonDecode(response.body);
        setState(() => _errorMessage = error['detail'] ?? "Login Failed");
      }
    } on TimeoutException catch (_) {
       setState(() => _errorMessage = "Server Timeout: Is the backend running?");
    } catch (e) {
      setState(() => _errorMessage = "Connection Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDriver = _selectedRole == 'Driver';
    bool isAgency = _selectedRole == 'Agency';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_taxi, size: 80, color: Color(0xFFFFC107)),
              Text("VELOCAB", style: GoogleFonts.oswald(fontSize: 40, fontWeight: FontWeight.bold, color: const Color(0xFF1A237E))),
              
              const SizedBox(height: 30),

              // ROLE TOGGLE
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.grey.shade300)),
                child: Row(
                  children: ["Admin", "Agency", "Driver"].map((role) {
                    bool isSelected = _selectedRole == role;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedRole = role; 
                          _errorMessage = "";
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF1A237E) : Colors.transparent,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          alignment: Alignment.center,
                          child: Text(role.toUpperCase(), style: GoogleFonts.oswald(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 30),

              if (isDriver) ...[
                // DRIVER FIELDS
                TextField(controller: _agencyEmailController, decoration: _inputDec("AGENCY EMAIL", Icons.business)), 
                const SizedBox(height: 15),
                TextField(controller: _vanNumberController, decoration: _inputDec("VAN NUMBER", Icons.directions_bus)),
              ] else ...[
                // AGENCY/ADMIN FIELDS
                TextField(controller: _emailController, decoration: _inputDec("EMAIL ADDRESS", Icons.email)),
              ],
              
              const SizedBox(height: 15),
              TextField(controller: _passwordController, obscureText: true, decoration: _inputDec("PASSWORD", Icons.lock)),

              const SizedBox(height: 25),

              _isLoading 
                ? const CircularProgressIndicator()
                : SizedBox(
                  width: double.infinity, 
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107), foregroundColor: Colors.black),
                    child: Text("LOGIN", style: GoogleFonts.oswald(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),

              if (_errorMessage.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 15), child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
            
              // REGISTRATION LINK 
              if (isAgency) ...[
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen(serverUrl: widget.serverUrl)));
                  },
                  child: Text("New Agency? Register Here", style: GoogleFonts.lato(fontSize: 16, color: const Color(0xFF1A237E), fontWeight: FontWeight.bold)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    );
  }
}

// REGISTER SCREEN 
class RegisterScreen extends StatefulWidget {
  final String serverUrl;
  const RegisterScreen({super.key, required this.serverUrl});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _register() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty || _nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }

    setState(() => _isLoading = true);
    final url = widget.serverUrl.replaceAll('/login', '');
    
    try {
      final response = await http.post(
        Uri.parse("$url/register"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": _emailCtrl.text,
          "password": _passCtrl.text,
          "role": "agency",
          "agency_name": _nameCtrl.text
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        if (!mounted) return;
        _showSuccessDialog();
      } else {
        final error = jsonDecode(response.body);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Error: ${error['detail'] ?? response.body}")));
      }
    } on TimeoutException catch (_) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.orange, content: Text("Server Timeout: Is backend running?")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Connection Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Registration Sent"),
        content: const Text("Your account has been created but is PENDING APPROVAL.\n\nPlease contact the School Admin to activate your account."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); 
              Navigator.pop(context); 
            },
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("AGENCY REGISTRATION", style: GoogleFonts.oswald()), backgroundColor: const Color(0xFF1A237E)),
      backgroundColor: const Color(0xFFF5F5F5),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            TextField(controller: _nameCtrl, decoration: _inputDec("Agency Name", Icons.business)),
            const SizedBox(height: 15),
            TextField(controller: _emailCtrl, decoration: _inputDec("Email Address", Icons.email)),
            const SizedBox(height: 15),
            TextField(controller: _passCtrl, obscureText: true, decoration: _inputDec("Password", Icons.lock)),
            const SizedBox(height: 30),
            
            _isLoading 
              ? const CircularProgressIndicator()
              : SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _register,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: Text("REGISTER", style: GoogleFonts.oswald(color: Colors.white, fontSize: 18)),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    );
  }
}
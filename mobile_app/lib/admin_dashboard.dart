import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart'; 

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.serverUrl});
  final String serverUrl;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String get baseUrl => widget.serverUrl.replaceAll('/login', '');

  List _pendingAgencies = [];
  List _activeAgencies = [];

  List _pendingVans = [];
  List _activeVans = [];

  List _pendingDrivers = [];
  List _activeDrivers = [];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchAgencies(),
      _fetchVans(),
      _fetchDrivers(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchAgencies() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/registrations"));
      if (res.statusCode == 200) {
        List all = jsonDecode(res.body);
        setState(() {
          _pendingAgencies = all.where((i) => i['status'] == 'pending').toList();
          _activeAgencies = all.where((i) => i['status'] == 'approved').toList();
        });
      }
    } catch (e) { debugPrint("Error Agencies: $e"); }
  }

  Future<void> _fetchVans() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/vans/super_admin"));
      if (res.statusCode == 200) {
        List all = jsonDecode(res.body);
        setState(() {
          _pendingVans = all.where((v) => v['status'] == 'pending').toList();
          _activeVans = all.where((v) => v['status'] != 'pending').toList();
        });
      }
    } catch (e) { debugPrint("Error Vans: $e"); }
  }

  Future<void> _fetchDrivers() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/drivers/super_admin"));
      if (res.statusCode == 200) {
        List all = jsonDecode(res.body);
        setState(() {
          _pendingDrivers = all.where((d) => d['status'] == 'pending').toList();
          _activeDrivers = all.where((d) => d['status'] != 'pending').toList();
        });
      }
    } catch (e) { debugPrint("Error Drivers: $e"); }
  }

  Future<void> _approve(String category, String itemId) async {
    final url = "$baseUrl/approve/$category/$itemId";
    try {
      final response = await http.post(Uri.parse(url));
      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${category.toUpperCase()} Approved!"), backgroundColor: Colors.green)
        );
        _refreshAll();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection Error"), backgroundColor: Colors.red));
    }
  }

  void _logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen(serverUrl: widget.serverUrl)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2C3E50),
          title: Text("SUPER ADMIN", style: GoogleFonts.oswald(color: Colors.white, letterSpacing: 1)),
          centerTitle: true,
          actions: [
            IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _refreshAll),
            IconButton(icon: const Icon(Icons.logout, color: Colors.white70), onPressed: _logout),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF3498DB),
            labelColor: Color(0xFF3498DB),
            unselectedLabelColor: Colors.white54,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: "AGENCIES"),
              Tab(text: "VANS"),
              Tab(text: "DRIVERS"),
            ],
          ),
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                // Agencies Tab
                _buildSectionList(
                  pending: _pendingAgencies,
                  active: _activeAgencies,
                  category: 'users', 
                  idKey: 'id',
                  titleFunc: (m) => m['agency_name'] ?? m['username'] ?? 'Unknown',
                  subtitleFunc: (m) => "Email: ${m['email'] ?? 'N/A'}",
                ),

                // Vans Tab
                _buildSectionList(
                  pending: _pendingVans,
                  active: _activeVans,
                  category: 'van',
                  idKey: 'id',
                  titleFunc: (m) => "Van ${m['plate_number'] ?? m['van_number']}",
                  subtitleFunc: (m) => "Agency: ${m['agency_name'] ?? 'Unlinked'} • Seats: ${m['capacity']}",
                ),

                // Drivers Tab
                _buildSectionList(
                  pending: _pendingDrivers,
                  active: _activeDrivers,
                  category: 'driver', // Check main.py if it expects 'driver' or 'user'
                  idKey: 'id',
                  titleFunc: (m) => m['username'] ?? m['name'] ?? 'Unknown Driver',
                  subtitleFunc: (m) => "Agency: ${m['agency_name'] ?? 'Unlinked'}",
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildSectionList({
    required List pending,
    required List active,
    required String category,
    required String idKey,
    required String Function(Map) titleFunc,
    required String Function(Map) subtitleFunc,
  }) {
    if (pending.isEmpty && active.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text("No records found", style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // PENDING SECTION 
        if (pending.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text("PENDING APPROVAL (${pending.length})", 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
          ),
          ...pending.map((item) => _buildCard(item, category, idKey, titleFunc, subtitleFunc, isPending: true)),
          const SizedBox(height: 20),
        ],

        // ACTIVE SECTION 
        if (active.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text("ACTIVE DATABASE (${active.length})", 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
          ),
          ...active.map((item) => _buildCard(item, category, idKey, titleFunc, subtitleFunc, isPending: false)),
        ],
      ],
    );
  }

  Widget _buildCard(
    Map item, 
    String category, 
    String idKey, 
    String Function(Map) titleFunc, 
    String Function(Map) subtitleFunc,
    {required bool isPending}
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isPending ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
          child: Icon(
            isPending ? Icons.priority_high : Icons.check,
            color: isPending ? Colors.orange : Colors.green,
            size: 20,
          ),
        ),
        title: Text(
          titleFunc(item),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
        ),
        subtitle: Text(
          subtitleFunc(item),
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        trailing: isPending
            ? ElevatedButton(
                onPressed: () => _approve(category, item[idKey].toString()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text("APPROVE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              )
            : const Icon(Icons.verified_user, color: Colors.green, size: 20),
      ),
    );
  }
}
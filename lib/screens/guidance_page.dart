import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'clinics_page.dart';
import 'bookings_page.dart';
import 'doctor_dashboard_page.dart';

class GuidancePage extends StatefulWidget {
  const GuidancePage({super.key});

  @override
  State<GuidancePage> createState() => _GuidancePageState();
}

class _GuidancePageState extends State<GuidancePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'الإرشاد الطبي',
          style: GoogleFonts.cairo(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.blue,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          unselectedLabelStyle: GoogleFonts.cairo(
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
          tabs: [
            Tab(
              icon: Icon(Icons.local_hospital),
              text: 'العيادات',
            ),
            Tab(
              icon: Icon(Icons.calendar_today),
              text: 'الحجوزات',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ClinicsPage(),
          BookingsPage(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const DoctorDashboardPage(),
            ),
          );
        },
        backgroundColor: Colors.blue,
        child: const Icon(
          Icons.medical_services,
          color: Colors.white,
        ),
      ),
    );
  }
}
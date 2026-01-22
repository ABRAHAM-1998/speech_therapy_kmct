import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_therapy/src/features/slp/data/appointment_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class BookAppointmentSheet extends StatefulWidget {
  final Map<String, dynamic> slpData;
  final String slpId;

  const BookAppointmentSheet({
    super.key, 
    required this.slpData, 
    required this.slpId,
  });

  @override
  State<BookAppointmentSheet> createState() => _BookAppointmentSheetState();
}

class _BookAppointmentSheetState extends State<BookAppointmentSheet> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  bool _isBooking = false;

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _confirmBooking() async {
    setState(() => _isBooking = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      await AppointmentRepository().bookAppointment(
        patientId: user.uid,
        patientName: user.displayName ?? 'Patient',
        slpId: widget.slpId,
        slpName: widget.slpData['fullName'] ?? 'Specialist',
        dateTime: dateTime,
      );

      if (mounted) {
        Navigator.pop(context); // Close sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment Booked Successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Book Appointment",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          const SizedBox(height: 8),
          Text("with ${widget.slpData['fullName']}", style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 24),
          
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
            leading: const Icon(Icons.calendar_today, color: Colors.teal),
            title: Text(DateFormat('EEE, MMM d, y').format(_selectedDate), style: const TextStyle(color: Colors.black)),
            onTap: _selectDate,
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
            leading: const Icon(Icons.access_time, color: Colors.teal),
            title: Text(_selectedTime.format(context), style: const TextStyle(color: Colors.black)),
            onTap: _selectTime,
          ),
          
          const SizedBox(height: 32),
          
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _isBooking ? null : _confirmBooking,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
              ),
              child: _isBooking 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text("Confirm Booking", style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

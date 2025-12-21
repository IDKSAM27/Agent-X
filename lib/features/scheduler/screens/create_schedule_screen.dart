import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/scheduler_model.dart';
import '../services/scheduler_service.dart';

class CreateScheduleScreen extends StatefulWidget {
  const CreateScheduleScreen({super.key});

  @override
  State<CreateScheduleScreen> createState() => _CreateScheduleScreenState();
}

class _CreateScheduleScreenState extends State<CreateScheduleScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SchedulerService _schedulerService = SchedulerService();
  final ImagePicker _picker = ImagePicker();
  
  File? _selectedImage;
  final TextEditingController _textController = TextEditingController();
  
  bool _isAnalyzing = false;
  Schedule? _parsedSchedule;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _parsedSchedule = null;
        _error = null;
      });
    }
  }

  Future<void> _analyze() async {
    setState(() {
      _isAnalyzing = true;
      _error = null;
      _parsedSchedule = null;
    });

    try {
      Schedule result;
      if (_tabController.index == 0) {
        if (_selectedImage == null) {
          throw Exception("Please select an image first");
        }
        result = await _schedulerService.parseScheduleFromFile(_selectedImage!);
      } else {
        if (_textController.text.trim().isEmpty) {
          throw Exception("Please enter some text describing the schedule");
        }
        result = await _schedulerService.parseScheduleFromText(_textController.text);
      }

      setState(() {
        _parsedSchedule = result;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _saveSchedule() async {
    if (_parsedSchedule == null) return;

    setState(() {
      _isAnalyzing = true; // reusing loading state
    });

    try {
      await _schedulerService.createSchedule(_parsedSchedule!);
      if (mounted) {
        Navigator.pop(context, true); // Return true to refresh list
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Schedule'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Upload Image', icon: Icon(Icons.image)),
            Tab(text: 'Describe', icon: Icon(Icons.text_fields)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildImageTab(),
                _buildTextTab(),
              ],
            ),
          ),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red.withOpacity(0.1),
              width: double.infinity,
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_isAnalyzing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            )
          else if (_parsedSchedule != null)
            _buildConfirmationCard(),
            
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
               width: double.infinity,
               child: ElevatedButton(
                 onPressed: _isAnalyzing ? null : (_parsedSchedule == null ? _analyze : _saveSchedule),
                 style: ElevatedButton.styleFrom(
                   padding: const EdgeInsets.symmetric(vertical: 16),
                   backgroundColor: _parsedSchedule == null ? Theme.of(context).primaryColor : Colors.green,
                 ),
                 child: Text(
                    _parsedSchedule == null ? 'Analyze Schedule' : 'Save Schedule',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                 ),
               ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[100],
            ),
            child: _selectedImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_selectedImage!, fit: BoxFit.contain),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Tap below to select image'),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.image),
            label: const Text('Select Image'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Supported: Screenshots, Photos of timetables',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTextTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _textController,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'e.g. "I have Math on Monday 10-11am in Room 202, Physics on Tuesday 2-4pm..."',
              border: OutlineInputBorder(),
              filled: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationCard() {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
             BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                   const Icon(Icons.check_circle, color: Colors.green),
                   const SizedBox(width: 8),
                   Expanded(
                     child: Text(
                       'Found: ${_parsedSchedule!.name} (${_parsedSchedule!.items.length} items)',
                       style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                     ),
                   ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: _parsedSchedule!.items.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _parsedSchedule!.items[index];
                  return ListTile(
                    dense: true,
                    title: Text(item.subject),
                    subtitle: Text('${item.day} ${item.startTime}-${item.endTime}'),
                    leading: CircleAvatar(
                       child: Text(item.day.substring(0, 1)),
                       radius: 16,
                       backgroundColor: Colors.blue.withOpacity(0.1),
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

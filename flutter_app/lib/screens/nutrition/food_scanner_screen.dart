import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';

class FoodScannerScreen extends ConsumerStatefulWidget {
  const FoodScannerScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<FoodScannerScreen> createState() => _FoodScannerScreenState();
}

class _FoodScannerScreenState extends ConsumerState<FoodScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  Map<String, dynamic>? _analysisResult;
  bool _isAnalyzing = false;
  String? _error;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _imageFile = File(image.path);
        _analysisResult = null;
        _error = null;
      });

      await _analyzeImage();
    } catch (e) {
      setState(() {
        _error = 'Failed to pick image: $e';
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_imageFile == null) return;

    setState(() {
      _isAnalyzing = true;
      _error = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final result = await apiService.analyzeFoodImage(_imageFile!.path);

      setState(() {
        _analysisResult = result;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to analyze image: $e';
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _logMeal() async {
    if (_analysisResult == null) return;

    final foods = _analysisResult!['foods'] as List;
    final mealType = _analysisResult!['meal_type_suggestion'] ?? 'snack';

    // TODO: Implement actual meal logging
    // For now, just show a confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logged ${foods.length} food items as $mealType'),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Scanner'),
        actions: [
          if (_analysisResult != null)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _logMeal,
              tooltip: 'Log Meal',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_imageFile == null)
              _buildImagePickerButtons()
            else
              _buildImagePreview(),
            const SizedBox(height: 24),
            if (_isAnalyzing)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Analyzing food image...'),
                    SizedBox(height: 8),
                    Text(
                      'This may take a few seconds',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_analysisResult != null) _buildAnalysisResults(),
          ],
        ),
      ),
      floatingActionButton: _imageFile != null
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _imageFile = null;
                  _analysisResult = null;
                  _error = null;
                });
              },
              child: const Icon(Icons.refresh),
            )
          : null,
    );
  }

  Widget _buildImagePickerButtons() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Icon(
          Icons.camera_alt_outlined,
          size: 100,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 24),
        Text(
          'Scan Your Food',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Take a photo or upload an image to get nutritional information',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        ElevatedButton.icon(
          onPressed: () => _pickImage(ImageSource.camera),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Take Photo'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: const Text('Choose from Gallery'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Image.file(
            _imageFile!,
            height: 300,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
          if (_analysisResult == null && !_isAnalyzing)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _analyzeImage,
                icon: const Icon(Icons.search),
                label: const Text('Analyze Food'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalysisResults() {
    final foods = _analysisResult!['foods'] as List;
    final totalCalories = _analysisResult!['total_calories'] ?? 0;
    final mealType = _analysisResult!['meal_type_suggestion'] ?? 'snack';
    final notes = _analysisResult!['notes'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    const Text(
                      'Analysis Complete!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSummaryRow('Total Calories', '$totalCalories kcal'),
                _buildSummaryRow('Suggested Meal Type', mealType.toUpperCase()),
                _buildSummaryRow('Foods Detected', '${foods.length}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (notes.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(notes),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Detected Foods',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ...foods.map((food) => _buildFoodCard(food)),
      ],
    );
  }

  Widget _buildFoodCard(Map<String, dynamic> food) {
    final name = food['name'] ?? 'Unknown';
    final calories = food['calories'] ?? 0;
    final protein = food['protein_grams']?.toDouble() ?? 0.0;
    final carbs = food['carbs_grams']?.toDouble() ?? 0.0;
    final fat = food['fat_grams']?.toDouble() ?? 0.0;
    final servingSize = food['serving_size'] ?? 'N/A';
    final confidence = food['confidence']?.toDouble() ?? 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text('${(confidence * 100).toInt()}%'),
                  backgroundColor: confidence > 0.7
                      ? Colors.green.shade100
                      : confidence > 0.5
                          ? Colors.orange.shade100
                          : Colors.red.shade100,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Serving: $servingSize'),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNutrientColumn('Calories', '$calories', 'kcal'),
                _buildNutrientColumn('Protein', '${protein.toStringAsFixed(1)}', 'g'),
                _buildNutrientColumn('Carbs', '${carbs.toStringAsFixed(1)}', 'g'),
                _buildNutrientColumn('Fat', '${fat.toStringAsFixed(1)}', 'g'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientColumn(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

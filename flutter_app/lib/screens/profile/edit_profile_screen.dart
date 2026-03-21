import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ageController;
  late TextEditingController _weightController;
  late TextEditingController _heightController;
  String? _gender;
  String? _activityLevel;
  String? _primaryGoal;
  String? _fitnessExperience;
  List<String> _dietaryRestrictions = [];
  bool _isSaving = false;

  static const _activityLevels = [
    'sedentary',
    'lightly_active',
    'moderately_active',
    'very_active',
    'extremely_active',
  ];

  static const _goals = [
    'weight_loss',
    'muscle_gain',
    'maintenance',
    'endurance',
    'flexibility',
    'general_fitness',
  ];

  static const _fitnessLevels = [
    'beginner',
    'intermediate',
    'advanced',
  ];

  static const _dietaryOptions = [
    'vegetarian',
    'vegan',
    'gluten_free',
    'dairy_free',
    'nut_free',
    'halal',
    'kosher',
    'low_carb',
    'keto',
    'paleo',
  ];

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authNotifierProvider).profile;
    _ageController = TextEditingController(text: profile?.age?.toString() ?? '');
    _weightController = TextEditingController(text: profile?.weight?.toStringAsFixed(1) ?? '');
    _heightController = TextEditingController(text: profile?.height?.toStringAsFixed(0) ?? '');
    _gender = profile?.gender;
    _activityLevel = profile?.activityLevel;
    _primaryGoal = profile?.primaryGoal;
    _fitnessExperience = profile?.fitnessExperience;
    _dietaryRestrictions = List<String>.from(profile?.dietaryRestrictions ?? []);
  }

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  String _formatLabel(String value) {
    return value.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'age': int.tryParse(_ageController.text),
      'weight': double.tryParse(_weightController.text),
      'height': double.tryParse(_heightController.text),
      'gender': _gender,
      'activity_level': _activityLevel,
      'primary_goal': _primaryGoal,
      'fitness_experience': _fitnessExperience,
      'dietary_restrictions': _dietaryRestrictions,
    };

    final success = await ref.read(authNotifierProvider.notifier).updateProfile(data);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update profile'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Body Metrics
            Text('Body Metrics', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ageController,
                    decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder(), suffixText: 'years'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      final age = int.tryParse(v);
                      if (age == null || age < 13 || age > 120) return '13-120';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _gender,
                    decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
                    items: ['male', 'female', 'other'].map((g) => DropdownMenuItem(value: g, child: Text(_formatLabel(g)))).toList(),
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _weightController,
                    decoration: const InputDecoration(labelText: 'Weight', border: OutlineInputBorder(), suffixText: 'kg'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      final w = double.tryParse(v);
                      if (w == null || w < 20 || w > 300) return '20-300';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _heightController,
                    decoration: const InputDecoration(labelText: 'Height', border: OutlineInputBorder(), suffixText: 'cm'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      final h = double.tryParse(v);
                      if (h == null || h < 100 || h > 250) return '100-250';
                      return null;
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            Text('Activity & Goals', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _activityLevel,
              decoration: const InputDecoration(labelText: 'Activity Level', border: OutlineInputBorder()),
              items: _activityLevels.map((l) => DropdownMenuItem(value: l, child: Text(_formatLabel(l)))).toList(),
              onChanged: (v) => setState(() => _activityLevel = v),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _primaryGoal,
              decoration: const InputDecoration(labelText: 'Primary Goal', border: OutlineInputBorder()),
              items: _goals.map((g) => DropdownMenuItem(value: g, child: Text(_formatLabel(g)))).toList(),
              onChanged: (v) => setState(() => _primaryGoal = v),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _fitnessExperience,
              decoration: const InputDecoration(labelText: 'Fitness Experience', border: OutlineInputBorder()),
              items: _fitnessLevels.map((l) => DropdownMenuItem(value: l, child: Text(_formatLabel(l)))).toList(),
              onChanged: (v) => setState(() => _fitnessExperience = v),
            ),

            const SizedBox(height: 24),
            Text('Dietary Restrictions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dietaryOptions.map((opt) {
                final selected = _dietaryRestrictions.contains(opt);
                return FilterChip(
                  label: Text(_formatLabel(opt)),
                  selected: selected,
                  onSelected: (sel) {
                    setState(() {
                      if (sel) {
                        _dietaryRestrictions.add(opt);
                      } else {
                        _dietaryRestrictions.remove(opt);
                      }
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save Changes'),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

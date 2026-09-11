import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/session.dart';
import 'widgets.dart';

class InteractiveComposer extends StatefulWidget {
  const InteractiveComposer({
    super.key,
    required this.session,
    required this.path,
    required this.poll,
  });
  final SessionController session;
  final String path;
  final bool poll;
  @override
  State<InteractiveComposer> createState() => _InteractiveComposerState();
}

class _InteractiveComposerState extends State<InteractiveComposer> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _options = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  bool _multiple = false;
  bool _saving = false;
  DateTime _date = DateTime.now().add(const Duration(days: 1));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.session.api.request(
        'POST',
        widget.path,
        body: widget.poll
            ? {
                'question': _title.text.trim(),
                'options': _options.text
                    .split('\n')
                    .map((v) => v.trim())
                    .where((v) => v.isNotEmpty)
                    .toList(),
                'allow_multiple': _multiple,
              }
            : {
                'title': _title.text.trim(),
                'description': _description.text.trim(),
                'location': _location.text.trim(),
                'starts_at': _date.toUtc().toIso8601String(),
              },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (time != null && mounted) {
      setState(
        () => _date = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.poll ? 'Create a poll' : 'Create an event'),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.poll
                ? 'Make the decision together.'
                : 'Bring everyone together.',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _title,
            maxLength: widget.poll ? 300 : 180,
            decoration: InputDecoration(
              labelText: widget.poll ? 'Your question' : 'Event title',
            ),
            validator: (value) =>
                value!.trim().isEmpty ? 'This field is required' : null,
          ),
          const SizedBox(height: 12),
          if (widget.poll) ...[
            TextFormField(
              controller: _options,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: 'Options',
                hintText: 'One option per line\nFor example:\nMonday\nTuesday',
              ),
              validator: (value) {
                final options = value!
                    .split('\n')
                    .map((v) => v.trim())
                    .where((v) => v.isNotEmpty)
                    .toList();
                if (options.length < 2 || options.length > 10) {
                  return 'Add between 2 and 10 options';
                }
                if (options.any((v) => v.length > 120)) {
                  return 'Keep each option under 120 characters';
                }
                if (options.map((v) => v.toLowerCase()).toSet().length !=
                    options.length) {
                  return 'Each option must be different';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow multiple answers'),
              value: _multiple,
              onChanged: (value) => setState(() => _multiple = value),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Date and time'),
              subtitle: Text(
                DateFormat('EEE, MMM d, y · h:mm a').format(_date),
              ),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _location,
              maxLength: 180,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              minLines: 4,
              maxLines: 8,
              maxLength: 5000,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: 'Description (optional)',
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? 'Sharing…'
                  : widget.poll
                  ? 'Share poll'
                  : 'Share event',
            ),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    _title.dispose();
    _options.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }
}

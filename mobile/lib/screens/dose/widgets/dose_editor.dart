part of '../dose_screen.dart';

/// Opens the schedule editor as a modal sheet. Returns true when something was
/// saved or deleted, so the caller can refresh.
///
/// This is the screen that was missing entirely: [DoseService.addSchedule] had
/// no caller anywhere in the app, so dose reminders, adherence, streaks and
/// refill tracking could never be reached by a real user. Everything the Dose
/// page renders now originates here.
Future<bool> showDoseScheduleEditor(
  BuildContext context, {
  DoseSchedule? existing,
  required String userId,
  required DateTime now,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) =>
        _DoseScheduleEditor(existing: existing, userId: userId, now: now),
  );
  return saved ?? false;
}

/// The editor's validatable fields, so an error can be attached to the control
/// that produced it.
enum _Field { medicine, amount, times, supply }

class _DoseScheduleEditor extends StatefulWidget {
  const _DoseScheduleEditor({
    required this.existing,
    required this.userId,
    required this.now,
  });

  final DoseSchedule? existing;
  final String userId;
  final DateTime now;

  @override
  State<_DoseScheduleEditor> createState() => _DoseScheduleEditorState();
}

class _DoseScheduleEditorState extends State<_DoseScheduleEditor> {
  static const List<String> _units = [
    'mg',
    'g',
    'mcg',
    'mL',
    'IU',
    'tablet',
    'capsule',
    'puff',
    'drop',
    'unit',
  ];

  final TextEditingController _amount = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _quantityFocus = FocusNode();

  List<UserMedication> _medications = const [];
  bool _loadingMedications = true;
  bool _saving = false;

  UserMedication? _medication;
  String _unit = 'mg';
  DoseFrequency _frequency = DoseFrequency.onceDaily;
  List<String> _slots = const ['08:00'];
  late DateTime _startDate;
  DateTime? _endDate;

  /// Field-level validation messages, keyed by [_Field]. Errors are shown
  /// against the field that caused them rather than as a snackbar the user has
  /// to map back onto the form themselves, and each clears the moment that
  /// field is edited.
  final Map<_Field, String> _errors = <_Field, String>{};

  bool get _isEditing => widget.existing != null;

  void _clearError(_Field field) {
    if (!_errors.containsKey(field)) return;
    setState(() => _errors.remove(field));
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _startDate = existing?.startDate ?? _dateOnly(widget.now);
    if (existing != null) {
      // A schedule saved without a strength reopens with the field empty, not
      // showing a "0" the user then has to delete.
      if (existing.hasAmount) _amount.text = _trimAmount(existing.amount);
      _unit = existing.unit;
      _frequency = existing.frequency;
      _slots = List<String>.from(existing.timeSlots);
      _endDate = existing.endDate;
      if (existing.quantity != null) {
        _quantity.text = _trimAmount(existing.quantity!);
      }
    } else {
      _slots = _defaultSlots(_frequency);
    }
    // The summary at the foot of the form restates what will be saved, so it
    // has to track the text fields as they are typed, not only the pickers.
    _amount.addListener(_onTextChanged);
    _quantity.addListener(_onTextChanged);
    _loadMedications();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amount
      ..removeListener(_onTextChanged)
      ..dispose();
    _quantity
      ..removeListener(_onTextChanged)
      ..dispose();
    _amountFocus.dispose();
    _quantityFocus.dispose();
    super.dispose();
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _trimAmount(double value) {
    final rounded = value.roundToDouble();
    return value == rounded ? rounded.toInt().toString() : value.toString();
  }

  /// Sensible default clock times per frequency, so the user starts from a
  /// working schedule instead of an empty list they must build by hand.
  static List<String> _defaultSlots(DoseFrequency frequency) {
    return switch (frequency) {
      DoseFrequency.onceDaily => ['08:00'],
      DoseFrequency.twiceDaily => ['08:00', '20:00'],
      DoseFrequency.threeDaily => ['08:00', '14:00', '20:00'],
      DoseFrequency.every8h => ['06:00', '14:00', '22:00'],
      DoseFrequency.asNeeded => const [],
    };
  }

  Future<void> _loadMedications() async {
    try {
      final medications = await UserDataService.instance.getUserMedications(
        widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _medications = medications;
        _loadingMedications = false;
        final existing = widget.existing;
        if (existing != null) {
          _medication = medications
              .where((m) => m.drugId == existing.drugId)
              .firstOrNull;
        } else if (medications.length == 1) {
          // Only one medicine saved — pre-select it; there is no choice to make.
          _medication = medications.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMedications = false);
    }
  }

  void _selectFrequency(DoseFrequency frequency) {
    setState(() {
      _frequency = frequency;
      // Reseed the times to match the new frequency, but keep whatever the
      // user already chose where the counts line up — retyping four times
      // because you toggled a chip is infuriating.
      final defaults = _defaultSlots(frequency);
      if (_slots.length != defaults.length) {
        _slots = defaults;
      }
    });
  }

  Future<void> _editSlot(int index) async {
    final parts = _slots[index].split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: context.colors.accent),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    setState(() {
      _slots = [..._slots]
        ..[index] =
            '${picked.hour.toString().padLeft(2, '0')}:'
            '${picked.minute.toString().padLeft(2, '0')}'
        ..sort();
    });
  }

  void _addSlot() {
    setState(() {
      _slots = [..._slots, '12:00']..sort();
    });
  }

  void _removeSlot(int index) {
    setState(() => _slots = [..._slots]..removeAt(index));
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : (_endDate ?? _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(widget.now.year - 1),
      lastDate: DateTime(widget.now.year + 5),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: context.colors.accent),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = _dateOnly(picked);
        // An end date that now precedes the start is meaningless — clear it
        // rather than silently persisting a schedule that can never fire.
        if (_endDate != null && _endDate!.isBefore(_startDate)) _endDate = null;
      } else {
        _endDate = _dateOnly(picked);
      }
    });
  }

  /// Validates every field at once and returns the messages, so the user sees
  /// everything that needs fixing in one pass rather than being sent back for
  /// each problem in turn.
  Map<_Field, String> _validate() {
    final errors = <_Field, String>{};
    if (_medication == null) {
      errors[_Field.medicine] = 'Choose which medicine this schedule is for.';
    }
    // The strength is OPTIONAL: an empty amount is a perfectly valid schedule
    // ("one tablet, morning and night"). Only a value that was typed and makes
    // no sense is an error.
    final amountText = _amount.text.trim();
    if (amountText.isNotEmpty) {
      final amount = double.tryParse(amountText);
      if (amount == null) {
        errors[_Field.amount] = 'Use numbers only, for example 500.';
      } else if (amount <= 0) {
        errors[_Field.amount] = 'The amount must be greater than zero.';
      }
    }
    if (_frequency.isScheduled && _slots.isEmpty) {
      errors[_Field.times] = 'Add at least one time of day.';
    }
    final quantityText = _quantity.text.trim();
    if (quantityText.isNotEmpty) {
      final quantity = double.tryParse(quantityText);
      if (quantity == null) {
        errors[_Field.supply] = 'Use numbers only, for example 30.';
      } else if (quantity <= 0) {
        errors[_Field.supply] = 'The quantity must be greater than zero.';
      }
    }
    return errors;
  }

  Future<void> _save() async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
      });
      // Put the keyboard where the first problem is, so the fix is one tap away.
      if (errors.containsKey(_Field.amount)) {
        _amountFocus.requestFocus();
      } else if (errors.containsKey(_Field.supply)) {
        _quantityFocus.requestFocus();
      }
      return;
    }
    setState(() {
      _errors.clear();
      _saving = true;
    });

    final medication = _medication!;
    final quantityText = _quantity.text.trim();
    final schedule = DoseSchedule(
      id: widget.existing?.id ?? 0,
      userId: widget.userId,
      drugId: medication.drugId,
      drugName: medication.displayName,
      // 0 is the stored form of "no strength recorded" — see
      // [DoseSchedule.hasAmount].
      amount: double.tryParse(_amount.text.trim()) ?? 0,
      unit: _unit,
      frequency: _frequency,
      timeSlots: _frequency.isScheduled ? _slots : const [],
      startDate: _startDate,
      endDate: _endDate,
      quantity: quantityText.isEmpty ? null : double.parse(quantityText),
      createdAt: widget.existing?.createdAt ?? widget.now,
    );

    try {
      final DoseSchedule persisted;
      if (_isEditing) {
        await DoseService.instance.updateSchedule(schedule);
        persisted = schedule;
      } else {
        final id = await DoseService.instance.addSchedule(schedule);
        persisted = schedule.copyWith(id: id);
      }
      // Re-plan the OS reminders for this schedule. Never fatal: a device that
      // refuses notifications must still keep the saved schedule.
      try {
        await DoseReminderScheduler.instance.syncSchedule(persisted);
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnack.error(context, "Couldn't save this schedule. Please try again.");
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showConfirmSheet(
      context: context,
      title: 'Remove this schedule?',
      message:
          '${existing.drugName} will stop appearing on your timeline and its '
          'reminders will be cancelled. Doses you have already logged are '
          'kept.',
      confirmLabel: 'Remove',
      cancelLabel: 'Keep',
      destructive: true,
      icon: Icons.alarm_off_rounded,
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await DoseService.instance.removeSchedule(existing.id);
      try {
        await DoseReminderScheduler.instance.cancelForSchedule(existing.id);
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnack.error(context, "Couldn't remove this schedule.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final viewInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: BoxDecoration(
          color: colors.scaffold,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(responsive.radius(26)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: responsive.s(10)),
            Container(
              width: responsive.s(38),
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            // ── Title row: an explicit Close on the left (a drag-down is not
            // a discoverable way out of a form), the title, and Delete only
            // when there is something to delete. ────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                responsive.s(10),
                responsive.s(10),
                responsive.s(10),
                responsive.s(6),
              ),
              child: Row(
                children: [
                  _EditorIconButton(
                    icon: Icons.close_rounded,
                    semanticLabel: 'Close without saving',
                    onTap: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isEditing ? 'Edit schedule' : 'New dose schedule',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: colors.ink,
                            fontSize: responsive.font(16.5),
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            height: 1.2,
                          ),
                        ),
                        SizedBox(height: responsive.s(3)),
                        // What saving this actually sets up. A form this long
                        // deserves one line explaining why it is worth filling.
                        Text(
                          'Reminders, adherence and refills follow from this.',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: colors.inkMute,
                            fontSize: responsive.font(11.4),
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // A balanced trailing slot: the delete action when editing,
                  // otherwise an equal-width spacer so the title stays on the
                  // sheet's true centre line.
                  if (_isEditing)
                    _EditorIconButton(
                      icon: Icons.delete_outline_rounded,
                      semanticLabel: 'Delete this schedule',
                      tone: colors.danger,
                      onTap: _saving ? null : _delete,
                    )
                  else
                    SizedBox(width: responsive.s(40).clamp(38.0, 46.0)),
                ],
              ),
            ),
            Divider(color: colors.border, height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                // Dragging the form closes the keyboard, so the fields below
                // the fold are reachable without a separate dismiss tap.
                keyboardDismissBehavior: kDismissKeyboardOnDrag,
                padding: EdgeInsets.fromLTRB(
                  responsive.pageX,
                  responsive.s(20),
                  responsive.pageX,
                  responsive.s(20),
                ),
                children: [
                  // The form is three questions, not eleven fields, so it is
                  // laid out as three grouped panels — what, when, and how
                  // much you hold — each numbered and each on its own card.
                  // Flat labels stacked down a single column gave every field
                  // the same weight and made a two-minute task look like a
                  // form to be endured.

                  // ── 1. What ────────────────────────────────────────────
                  _EditorGroup(
                    step: 1,
                    title: 'The medicine',
                    caption: 'Which medicine this schedule is for.',
                    children: [
                      const _EditorLabel(text: 'Medicine'),
                      SizedBox(height: responsive.s(10)),
                      _MedicinePicker(
                        medications: _medications,
                        selected: _medication,
                        loading: _loadingMedications,
                        invalid: _errors.containsKey(_Field.medicine),
                        onSelected: (medication) {
                          setState(() => _medication = medication);
                          _clearError(_Field.medicine);
                        },
                        onAddMedicine: () {
                          Navigator.of(context).pop(false);
                          Navigator.of(
                            context,
                          ).pushNamed(SearchScreen.routeName);
                        },
                      ),
                      _FieldError(message: _errors[_Field.medicine]),
                      SizedBox(height: responsive.s(20)),
                      const _EditorLabel(text: 'Strength', optional: true),
                      SizedBox(height: responsive.s(10)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _EditorField(
                              controller: _amount,
                              focusNode: _amountFocus,
                              hint: 'e.g. 500',
                              invalid: _errors.containsKey(_Field.amount),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => _clearError(_Field.amount),
                              onSubmitted: (_) => _quantityFocus.requestFocus(),
                            ),
                          ),
                          SizedBox(width: responsive.s(10)),
                          Expanded(
                            flex: 2,
                            child: _UnitDropdown(
                              value: _unit,
                              units: _units,
                              onChanged: (unit) => setState(() => _unit = unit),
                            ),
                          ),
                        ],
                      ),
                      _FieldError(message: _errors[_Field.amount]),
                      SizedBox(height: responsive.s(7)),
                      const _EditorHint(
                        text:
                            "Leave this blank if you don't know the strength — "
                            'the reminder works either way.',
                      ),
                    ],
                  ),

                  // ── 2. When ────────────────────────────────────────────
                  SizedBox(height: responsive.s(14)),
                  _EditorGroup(
                    step: 2,
                    title: 'The timing',
                    caption: 'When the reminders should fire.',
                    children: [
                      const _EditorLabel(text: 'How often'),
                      SizedBox(height: responsive.s(10)),
                      _FrequencyPicker(
                        value: _frequency,
                        onChanged: _selectFrequency,
                      ),
                      if (_frequency.isScheduled) ...[
                        SizedBox(height: responsive.s(20)),
                        _EditorLabel(
                          text: 'Times',
                          trailing: Pressable(
                            onTap: _addSlot,
                            pressScale: 0.92,
                            semanticLabel: 'Add another time',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  color: colors.accent,
                                  size: responsive.icon(15),
                                ),
                                SizedBox(width: responsive.s(3)),
                                Text(
                                  'Add time',
                                  style: GoogleFonts.inter(
                                    color: colors.accent,
                                    fontSize: responsive.font(12),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: responsive.s(10)),
                        _SlotEditor(
                          slots: _slots,
                          onEdit: _editSlot,
                          onRemove: _slots.length > 1 ? _removeSlot : null,
                        ),
                        _FieldError(message: _errors[_Field.times]),
                      ] else ...[
                        SizedBox(height: responsive.s(10)),
                        const _EditorHint(
                          text:
                              'An as-needed medicine is never put on the '
                              'calendar, so it sets no reminders — it stays '
                              'here for your records and for safety checks.',
                        ),
                      ],
                      SizedBox(height: responsive.s(20)),
                      const _EditorLabel(text: 'Dates'),
                      SizedBox(height: responsive.s(10)),
                      Row(
                        children: [
                          Expanded(
                            child: _DateField(
                              label: 'Starts',
                              value: _startDate,
                              onTap: () => _pickDate(isStart: true),
                            ),
                          ),
                          SizedBox(width: responsive.s(10)),
                          Expanded(
                            child: _DateField(
                              label: 'Ends',
                              value: _endDate,
                              placeholder: 'Ongoing',
                              onTap: () => _pickDate(isStart: false),
                              onClear: _endDate == null
                                  ? null
                                  : () => setState(() => _endDate = null),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ── 3. Optional supply tracking, last because it is. ───
                  SizedBox(height: responsive.s(14)),
                  _EditorGroup(
                    step: 3,
                    title: 'The supply',
                    caption: 'Optional — powers refill reminders.',
                    children: [
                      const _EditorLabel(text: 'Quantity', optional: true),
                      SizedBox(height: responsive.s(10)),
                      _EditorField(
                        controller: _quantity,
                        focusNode: _quantityFocus,
                        hint: 'How many were you dispensed?',
                        invalid: _errors.containsKey(_Field.supply),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => _clearError(_Field.supply),
                      ),
                      _FieldError(message: _errors[_Field.supply]),
                      SizedBox(height: responsive.s(7)),
                      const _EditorHint(
                        text:
                            'Used to estimate when your supply runs out and '
                            'when to reorder.',
                      ),
                    ],
                  ),

                  // ── The plain-English result, restated ─────────────────
                  //
                  // The last thing read before the Save button is what saving
                  // will actually do. Everything above is fields; this is the
                  // outcome, and it is the only place the user can check the
                  // whole schedule in one sentence.
                  SizedBox(height: responsive.s(18)),
                  _ScheduleSummary(
                    medication: _medication,
                    amount: _amount.text,
                    unit: _unit,
                    frequency: _frequency,
                    slots: _slots,
                    startDate: _startDate,
                    endDate: _endDate,
                    today: _dateOnly(widget.now),
                  ),
                ],
              ),
            ),
            // ── The actions, pinned above the keyboard: the primary save and
            // an equally reachable cancel, so leaving the form never depends on
            // finding the small ✕ or guessing at a drag. ───────────────────
            Divider(color: colors.border, height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                responsive.pageX,
                responsive.s(14),
                responsive.pageX,
                responsive.s(14) + MediaQuery.paddingOf(context).bottom * 0.4,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _EditorButton(
                      label: 'Cancel',
                      primary: false,
                      onTap: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ),
                  SizedBox(width: responsive.s(10)),
                  Expanded(
                    flex: 3,
                    child: _EditorButton(
                      label: _isEditing ? 'Save changes' : 'Create schedule',
                      primary: true,
                      busy: _saving,
                      onTap: _saving ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One numbered panel of the form.
///
/// The number is the point: it turns a long scroll into a short, countable
/// sequence, so the user can see at a glance that there are three things to do
/// and where they are in them. The card is the same surface, radius and border
/// as every panel on the Dose page itself, so the sheet reads as part of that
/// page rather than as a system form dropped on top of it.
class _EditorGroup extends StatelessWidget {
  const _EditorGroup({
    required this.step,
    required this.title,
    required this.caption,
    required this.children,
  });

  final int step;
  final String title;
  final String caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final disc = responsive.s(24).clamp(22.0, 28.0).toDouble();

    return _DoseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: disc,
                height: disc,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentAlpha(0.12),
                ),
                child: Text(
                  '$step',
                  style: GoogleFonts.inter(
                    color: colors.accent,
                    fontSize: responsive.font(12),
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(15),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: responsive.s(2)),
                    Text(
                      caption,
                      style: GoogleFonts.inter(
                        color: colors.inkMute,
                        fontSize: responsive.font(11.6),
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(16)),
          Divider(color: colors.border, height: 1),
          SizedBox(height: responsive.s(16)),
          ...children,
        ],
      ),
    );
  }
}

/// The one helper-text treatment in the form, so every explanatory line under a
/// field is the same size, colour and leading.
class _EditorHint extends StatelessWidget {
  const _EditorHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Text(
      text,
      style: GoogleFonts.inter(
        color: context.colors.inkMute,
        fontSize: responsive.font(11.6),
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
    );
  }
}

/// The schedule restated in one plain sentence, directly above the Save button.
///
/// A form can be filled correctly and still not be the schedule the user meant
/// — "twice daily at 08:00 and 20:00 from 29 July, ongoing" is checkable in a
/// second, where eleven separate controls are not. It stays honest while the
/// form is incomplete: it says what is still missing rather than inventing a
/// sentence out of half the answers.
class _ScheduleSummary extends StatelessWidget {
  const _ScheduleSummary({
    required this.medication,
    required this.amount,
    required this.unit,
    required this.frequency,
    required this.slots,
    required this.startDate,
    required this.endDate,
    required this.today,
  });

  final UserMedication? medication;
  final String amount;
  final String unit;
  final DoseFrequency frequency;
  final List<String> slots;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime today;

  /// "08:00 and 20:00", "08:00, 14:00 and 20:00" — a list a person would read
  /// aloud, not a comma-separated dump.
  String _times() {
    // The same formatter the time chips above use, so the sentence and the
    // controls it summarises can never disagree about how a time is written.
    final pretty = [
      for (final slot in slots) DoseService.formatSlotForDisplay(slot),
    ];
    if (pretty.isEmpty) return '';
    if (pretty.length == 1) return pretty.first;
    return '${pretty.take(pretty.length - 1).join(', ')} and ${pretty.last}';
  }

  String _day(DateTime date) {
    if (date == today) return 'today';
    if (date == today.add(const Duration(days: 1))) return 'tomorrow';
    return '${date.day} ${_monthNames[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final chosen = medication;

    final incomplete =
        chosen == null || (frequency.isScheduled && slots.isEmpty);
    if (incomplete) {
      return _SummaryShell(
        icon: Icons.edit_note_rounded,
        tone: colors.inkMute,
        title: 'Not ready yet',
        body: chosen == null
            ? 'Choose a medicine above and this will show exactly what gets '
                  'saved.'
            : 'Add at least one time of day and this will show exactly what '
                  'gets saved.',
      );
    }

    final strength = amount.trim().isEmpty ? '' : ' ${amount.trim()} $unit';
    final when = frequency.isScheduled
        ? '${frequency.label.toLowerCase()} at ${_times()}'
        : 'as needed — no reminders';
    final until = endDate == null ? 'ongoing' : 'until ${_day(endDate!)}';

    return _SummaryShell(
      icon: Icons.check_circle_rounded,
      tone: colors.accent,
      title: '${chosen.displayName}$strength',
      body:
          '${when.substring(0, 1).toUpperCase()}${when.substring(1)}, '
          'starting ${_day(startDate)}, $until.',
      dense: responsive.isCompactPhone,
    );
  }
}

/// The summary's surface — a tinted panel that changes tone with its state, so
/// "ready" and "not ready yet" are distinguishable without reading.
class _SummaryShell extends StatelessWidget {
  const _SummaryShell({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    this.dense = false,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(dense ? 13 : 15)),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(responsive.radius(18)),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: responsive.icon(18)),
          SizedBox(width: responsive.s(11)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(13.6),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: responsive.s(4)),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: colors.inkSoft,
                    fontSize: responsive.font(12.2),
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorLabel extends StatelessWidget {
  const _EditorLabel({
    required this.text,
    this.trailing,
    this.optional = false,
  });

  final String text;
  final Widget? trailing;

  /// Marks a field the user can leave blank. Saying so on the label is kinder
  /// than saying it in a hint the user only reads after tapping in.
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: GoogleFonts.inter(
            color: colors.inkMute,
            fontSize: responsive.font(10.5),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        if (optional) ...[
          SizedBox(width: responsive.s(6)),
          Text(
            'optional',
            style: GoogleFonts.inter(
              color: colors.inkMute,
              fontSize: responsive.font(10.5),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// An inline validation message, shown directly beneath the control that
/// produced it. Collapses to nothing when there is no error, so the form does
/// not reserve dead space for messages that may never appear.
class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.only(top: responsive.s(7)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: colors.danger,
                    size: responsive.icon(14),
                  ),
                  SizedBox(width: responsive.s(6)),
                  Expanded(
                    child: Text(
                      message!,
                      style: GoogleFonts.inter(
                        color: colors.danger,
                        fontSize: responsive.font(11.8),
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// A round icon control in the sheet's title row, at a real 44pt touch target.
class _EditorIconButton extends StatelessWidget {
  const _EditorIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final size = responsive.s(40).clamp(38.0, 46.0).toDouble();
    return Pressable(
      onTap: onTap,
      pressScale: 0.9,
      semanticLabel: semanticLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          icon,
          color: tone ?? colors.inkSoft,
          size: responsive.icon(20),
        ),
      ),
    );
  }
}

/// The sheet's footer buttons. One shape, one height, one radius — the primary
/// filled in brand teal, the secondary a quiet outline, so which action commits
/// and which backs out is unmistakable at a glance.
class _EditorButton extends StatelessWidget {
  const _EditorButton({
    required this.label,
    required this.primary,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final bool primary;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final height = responsive.s(50).clamp(46.0, 56.0).toDouble();
    final disabled = onTap == null;

    return Pressable(
      onTap: onTap,
      pressScale: 0.97,
      semanticLabel: label,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary
              ? (disabled ? colors.accentAlpha(0.4) : MedGuardPalette.teal)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(100),
          border: primary ? null : Border.all(color: colors.border),
        ),
        child: busy
            ? MorphLoader(
                size: responsive.s(21),
                color: MedGuardPalette.pureWhite,
                glow: false,
              )
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: primary ? MedGuardPalette.pureWhite : colors.inkSoft,
                  fontSize: responsive.font(14),
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// The saved-medicines picker. Schedules can only point at a medicine already
/// in the user's regimen — that is what keeps interaction checks, allergy
/// screening and the dose timeline all describing the same list.
class _MedicinePicker extends StatelessWidget {
  const _MedicinePicker({
    required this.medications,
    required this.selected,
    required this.loading,
    required this.onSelected,
    required this.onAddMedicine,
    this.invalid = false,
  });

  final List<UserMedication> medications;
  final UserMedication? selected;
  final bool loading;
  final ValueChanged<UserMedication> onSelected;
  final VoidCallback onAddMedicine;

  /// Nothing chosen when the form was submitted — the chips sit in a danger
  /// well so the error beneath has a target.
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    if (loading) {
      return Container(
        height: responsive.s(46),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(responsive.radius(14)),
        ),
      );
    }

    if (medications.isEmpty) {
      return Pressable(
        onTap: onAddMedicine,
        pressScale: 0.98,
        semanticLabel: 'Add a medicine first',
        child: Container(
          padding: EdgeInsets.all(responsive.s(14)),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(responsive.radius(14)),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                color: colors.accent,
                size: responsive.icon(19),
              ),
              SizedBox(width: responsive.s(10)),
              Expanded(
                child: Text(
                  'Add a medicine to your regimen first',
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(13),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.inkMute,
                size: responsive.icon(19),
              ),
            ],
          ),
        ),
      );
    }

    final chips = Wrap(
      spacing: responsive.s(8),
      runSpacing: responsive.s(8),
      children: [
        for (final medication in medications)
          _ChoiceChip(
            label: medication.displayName,
            selected: medication.drugId == selected?.drugId,
            onTap: () => onSelected(medication),
          ),
      ],
    );

    if (!invalid) return chips;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(10)),
      decoration: BoxDecoration(
        color: colors.dangerAlpha(0.06),
        borderRadius: BorderRadius.circular(responsive.radius(16)),
        border: Border.all(color: colors.danger, width: 1.2),
      ),
      child: chips,
    );
  }
}

class _FrequencyPicker extends StatelessWidget {
  const _FrequencyPicker({required this.value, required this.onChanged});

  final DoseFrequency value;
  final ValueChanged<DoseFrequency> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Wrap(
      spacing: responsive.s(8),
      runSpacing: responsive.s(8),
      children: [
        for (final frequency in DoseFrequency.values)
          _ChoiceChip(
            label: frequency.label,
            selected: frequency == value,
            onTap: () => onChanged(frequency),
          ),
      ],
    );
  }
}

/// The single selectable chip used by both pickers, so a medicine and a
/// frequency are chosen through an identical control.
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      pressScale: 0.95,
      semanticLabel: label,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(13),
          vertical: responsive.s(9),
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentAlpha(0.12) : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? colors.accentAlpha(0.42) : colors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? colors.accent : colors.inkSoft,
            fontSize: responsive.font(12.6),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SlotEditor extends StatelessWidget {
  const _SlotEditor({
    required this.slots,
    required this.onEdit,
    required this.onRemove,
  });

  final List<String> slots;
  final ValueChanged<int> onEdit;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Wrap(
      spacing: responsive.s(8),
      runSpacing: responsive.s(8),
      children: [
        for (var i = 0; i < slots.length; i++)
          Pressable(
            onTap: () => onEdit(i),
            pressScale: 0.95,
            semanticLabel: 'Change the ${slots[i]} dose time',
            child: Container(
              padding: EdgeInsets.only(
                left: responsive.s(12),
                right: onRemove == null ? responsive.s(12) : responsive.s(6),
                top: responsive.s(9),
                bottom: responsive.s(9),
              ),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: colors.accent,
                    size: responsive.icon(14),
                  ),
                  SizedBox(width: responsive.s(6)),
                  Text(
                    DoseService.formatSlotForDisplay(slots[i]),
                    style: GoogleFonts.inter(
                      color: colors.ink,
                      fontSize: responsive.font(12.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (onRemove != null) ...[
                    SizedBox(width: responsive.s(2)),
                    Pressable(
                      onTap: () => onRemove!(i),
                      pressScale: 0.85,
                      semanticLabel: 'Remove this time',
                      child: Padding(
                        padding: EdgeInsets.all(responsive.s(4)),
                        child: Icon(
                          Icons.close_rounded,
                          color: colors.inkMute,
                          size: responsive.icon(13),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.invalid = false,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Failed validation — the field carries a danger outline so the error text
  /// beneath it has something to point at.
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final radius = BorderRadius.circular(responsive.radius(14));
    // The resting outline is invisible until something is wrong, so the form
    // stays quiet in its normal state and the error genuinely stands out.
    OutlineInputBorder border(Color? color, double width) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: color == null
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: colors.accent,
      style: GoogleFonts.inter(
        color: colors.ink,
        fontSize: responsive.font(13.6),
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: invalid ? colors.dangerAlpha(0.06) : colors.surfaceAlt,
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          color: colors.inkMute,
          fontSize: responsive.font(13.2),
          fontWeight: FontWeight.w400,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: responsive.s(14),
          vertical: responsive.s(15),
        ),
        border: border(invalid ? colors.danger : null, 1.2),
        enabledBorder: border(invalid ? colors.danger : null, 1.2),
        focusedBorder: border(invalid ? colors.danger : colors.accent, 1.4),
      ),
    );
  }
}

class _UnitDropdown extends StatelessWidget {
  const _UnitDropdown({
    required this.value,
    required this.units,
    required this.onChanged,
  });

  final String value;
  final List<String> units;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    // A stored unit that is not in the standard list (an older schedule) still
    // has to be selectable, or opening the editor would silently rewrite it.
    final options = units.contains(value) ? units : [value, ...units];

    return Container(
      height: responsive.s(50).clamp(46.0, 56.0).toDouble(),
      padding: EdgeInsets.symmetric(horizontal: responsive.s(12)),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(responsive.radius(14)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(responsive.radius(14)),
          dropdownColor: colors.surface,
          icon: Icon(
            Icons.expand_more_rounded,
            color: colors.inkMute,
            size: responsive.icon(19),
          ),
          style: GoogleFonts.inter(
            color: colors.ink,
            fontSize: responsive.font(13.6),
            fontWeight: FontWeight.w500,
          ),
          items: [
            for (final unit in options)
              DropdownMenuItem<String>(value: unit, child: Text(unit)),
          ],
          onChanged: (unit) {
            if (unit != null) onChanged(unit);
          },
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String? placeholder;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      pressScale: 0.97,
      semanticLabel: label,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(13),
          vertical: responsive.s(11),
        ),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(responsive.radius(14)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(10.6),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: responsive.s(3)),
                  Text(
                    value == null
                        ? (placeholder ?? '—')
                        : '${_shortDate(value!)}, ${value!.year}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: value == null ? colors.inkMute : colors.ink,
                      fontSize: responsive.font(12.8),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              Pressable(
                onTap: onClear,
                pressScale: 0.85,
                semanticLabel: 'Clear end date',
                child: Icon(
                  Icons.close_rounded,
                  color: colors.inkMute,
                  size: responsive.icon(15),
                ),
              )
            else
              Icon(
                Icons.calendar_today_rounded,
                color: colors.inkMute,
                size: responsive.icon(15),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lists the user's schedules so one can be picked for editing. Shown only
/// when there is more than one — with a single schedule the manage action
/// opens it directly rather than making the user choose from a list of one.
class _SchedulePickerSheet extends StatelessWidget {
  const _SchedulePickerSheet({required this.schedules});

  final List<DoseSchedule> schedules;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      decoration: BoxDecoration(
        color: colors.scaffold,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(responsive.radius(26)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: responsive.s(10)),
          Container(
            width: responsive.s(38),
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              responsive.pageX,
              responsive.s(14),
              responsive.pageX,
              responsive.s(10),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Which schedule?',
                style: GoogleFonts.inter(
                  color: colors.ink,
                  fontSize: responsive.font(19),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                responsive.pageX,
                0,
                responsive.pageX,
                responsive.s(20) + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: schedules.length,
              separatorBuilder: (_, _) => SizedBox(height: responsive.s(8)),
              itemBuilder: (context, index) {
                final schedule = schedules[index];
                final times = schedule.timeSlots.isEmpty
                    ? schedule.frequency.label
                    : schedule.timeSlots
                          .map(DoseService.formatSlotForDisplay)
                          .join(' · ');
                return Pressable(
                  onTap: () => Navigator.of(context).pop(schedule),
                  pressScale: 0.98,
                  semanticLabel: 'Edit ${schedule.drugName}',
                  child: Container(
                    padding: EdgeInsets.all(responsive.s(14)),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(
                        responsive.radius(16),
                      ),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${schedule.drugName} ${schedule.doseLabel ?? ''}'
                                    .trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: colors.ink,
                                  fontSize: responsive.font(13.6),
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                              SizedBox(height: responsive.s(3)),
                              Text(
                                times,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: colors.inkSoft,
                                  fontSize: responsive.font(11.8),
                                  fontWeight: FontWeight.w500,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.inkMute,
                          size: responsive.icon(19),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

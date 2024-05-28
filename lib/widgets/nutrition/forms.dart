/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (C) 2020, 2021 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * wger Workout Manager is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:wger/exceptions/http_exception.dart';
import 'package:wger/helpers/consts.dart';
import 'package:wger/helpers/json.dart';
import 'package:wger/helpers/ui.dart';
import 'package:wger/models/nutrition/ingredient.dart';
import 'package:wger/models/nutrition/log.dart';
import 'package:wger/models/nutrition/meal.dart';
import 'package:wger/models/nutrition/meal_item.dart';
import 'package:wger/models/nutrition/nutritional_plan.dart';
import 'package:wger/providers/nutrition.dart';
import 'package:wger/screens/nutritional_plan_screen.dart';
import 'package:wger/widgets/nutrition/helpers.dart';
import 'package:wger/widgets/nutrition/widgets.dart';

class MealForm extends StatelessWidget {
  late final Meal _meal;
  final int _planId;

  final _form = GlobalKey<FormState>();
  final _timeController = TextEditingController();
  final _nameController = TextEditingController();

  MealForm(this._planId, [meal]) {
    _meal = meal ?? Meal(plan: _planId, time: TimeOfDay.fromDateTime(DateTime.now()));
    _timeController.text = timeToString(_meal.time)!;
    _nameController.text = _meal.name;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              key: const Key('field-time'),
              decoration: InputDecoration(labelText: AppLocalizations.of(context).time),
              controller: _timeController,
              onTap: () async {
                // Stop keyboard from appearing
                FocusScope.of(context).requestFocus(FocusNode());

                // Open time picker
                final pickedTime = await showTimePicker(
                  context: context,
                  initialTime: _meal.time!,
                );
                if (pickedTime != null) {
                  _timeController.text = timeToString(pickedTime)!;
                }
              },
              onSaved: (newValue) {
                _meal.time = stringToTime(newValue);
              },
              onFieldSubmitted: (_) {},
            ),
            TextFormField(
              maxLength: 25,
              key: const Key('field-name'),
              decoration: InputDecoration(labelText: AppLocalizations.of(context).name),
              controller: _nameController,
              onSaved: (newValue) {
                _meal.name = newValue as String;
              },
              onFieldSubmitted: (_) {},
            ),
            ElevatedButton(
              key: const Key(SUBMIT_BUTTON_KEY_NAME),
              child: Text(AppLocalizations.of(context).save),
              onPressed: () async {
                if (!_form.currentState!.validate()) {
                  return;
                }
                _form.currentState!.save();

                try {
                  _meal.id == null
                      ? Provider.of<NutritionPlansProvider>(context, listen: false)
                          .addMeal(_meal, _planId)
                      : Provider.of<NutritionPlansProvider>(context, listen: false).editMeal(_meal);
                } on WgerHttpException catch (error) {
                  showHttpExceptionErrorDialog(error, context);
                } catch (error) {
                  showErrorDialog(error, context);
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

Widget MealItemForm(Meal meal, List<MealItem> recent, [String? barcode, bool? test]) {
  return IngredientForm(
      // TODO we use planId 0 here cause we don't have one and we don't need it I think?
      recent: recent.map((e) => Log.fromMealItem(e, 0, e.mealId)).toList(),
      onSave: (BuildContext context, MealItem mealItem, DateTime? dt) {
        mealItem.mealId = meal.id!;
        Provider.of<NutritionPlansProvider>(context, listen: false).addMealItem(mealItem, meal);
      },
      barcode: barcode ?? '',
      test: test ?? false,
      withDate: false);
}

Widget IngredientLogForm(NutritionalPlan plan) {
  return IngredientForm(
      recent: plan.dedupDiaryEntries,
      onSave: (BuildContext context, MealItem mealItem, DateTime? dt) {
        Provider.of<NutritionPlansProvider>(context, listen: false)
            .logIngredientToDiary(mealItem, plan.id!, dt);
      },
      withDate: true);
}

/// IngredientForm is a form that lets the user pick an ingredient (and amount) to
/// log to the diary or to add to a meal.
class IngredientForm extends StatefulWidget {
  final Function(BuildContext context, MealItem mealItem, DateTime? dt) onSave;
  final List<Log> recent;
  final bool withDate;
  final String barcode;
  final bool test;

  const IngredientForm({
    required this.recent,
    required this.onSave,
    required this.withDate,
    this.barcode = '',
    this.test = false,
  });

  @override
  State<IngredientForm> createState() => IngredientFormState();
}

class IngredientFormState extends State<IngredientForm> {
  final _form = GlobalKey<FormState>();
  final _ingredientController = TextEditingController();
  final _ingredientIdController = TextEditingController();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController(); // optional
  final _timeController = TextEditingController(); // optional
  final _mealItem = MealItem.empty();
  var _searchQuery = ''; // copy from typeahead. for filtering suggestions

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateController.text = toDate(now)!;
    _timeController.text = timeToString(TimeOfDay.fromDateTime(now))!;
  }

  TextEditingController get ingredientIdController => _ingredientIdController;

  MealItem get mealItem => _mealItem;

  void selectIngredient(int id, String name, num? amount) {
    setState(() {
      _mealItem.ingredientId = id;
      _ingredientController.text = name;
      _ingredientIdController.text = id.toString();
      if (amount != null) {
        _amountController.text = amount.toStringAsFixed(0);
        _mealItem.amount = amount;
      }
    });
  }

// note: does not reset text search and amount inputs
  void unSelectIngredient() {
    setState(() {
      _mealItem.ingredientId = 0;
      _ingredientIdController.text = '';
    });
  }

  void updateSearchQuery(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String unit = AppLocalizations.of(context).g;
    final queryLower = _searchQuery.toLowerCase();
    final suggestions =
        widget.recent.where((e) => e.ingredient.name.toLowerCase().contains(queryLower)).toList();
    return Container(
      margin: const EdgeInsets.all(20),
      child: Form(
        key: _form,
        child: Column(
          children: [
            IngredientTypeahead(
              _ingredientIdController,
              _ingredientController,
              barcode: widget.barcode,
              test: widget.test,
              selectIngredient: selectIngredient,
              unSelectIngredient: unSelectIngredient,
              updateSearchQuery: updateSearchQuery,
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('field-weight'), // needed ?
                    decoration: InputDecoration(labelText: AppLocalizations.of(context).weight),
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (_) {},
                    onChanged: (value) {
                      setState(() {
                        final v = double.tryParse(value);
                        if (v != null) {
                          _mealItem.amount = v;
                        }
                      });
                    },
                    onSaved: (value) {
                      _mealItem.amount = double.parse(value!);
                    },
                    validator: (value) {
                      try {
                        double.parse(value!);
                      } catch (error) {
                        return AppLocalizations.of(context).enterValidNumber;
                      }
                      return null;
                    },
                  ),
                ),
                if (widget.withDate)
                  Expanded(
                    child: TextFormField(
                      readOnly: true,
                      // Stop keyboard from appearing
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).date,
                        // suffixIcon: const Icon(Icons.calendar_today),
                      ),
                      enableInteractiveSelection: false,
                      controller: _dateController,
                      onTap: () async {
                        // Show Date Picker Here
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(DateTime.now().year - 10),
                          lastDate: DateTime.now(),
                        );

                        if (pickedDate != null) {
                          _dateController.text = toDate(pickedDate)!;
                        }
                      },
                      onSaved: (newValue) {
                        _dateController.text = newValue!;
                      },
                    ),
                  ),
                if (widget.withDate)
                  Expanded(
                    child: TextFormField(
                      key: const Key('field-time'),
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).time,
                        //suffixIcon: const Icon(Icons.punch_clock)
                      ),
                      controller: _timeController,
                      onTap: () async {
                        // Stop keyboard from appearing
                        FocusScope.of(context).requestFocus(FocusNode());

                        // Open time picker
                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: stringToTime(_timeController.text),
                        );
                        if (pickedTime != null) {
                          _timeController.text = timeToString(pickedTime)!;
                        }
                      },
                      onSaved: (newValue) {
                        _timeController.text = newValue!;
                      },
                      onFieldSubmitted: (_) {},
                    ),
                  ),
              ],
            ),
            if (ingredientIdController.text.isNotEmpty && _amountController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Text(
                      'Macros preview',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    FutureBuilder<Ingredient>(
                      future: Provider.of<NutritionPlansProvider>(context, listen: false)
                          .fetchIngredient(_mealItem.ingredientId),
                      builder: (BuildContext context, AsyncSnapshot<Ingredient> snapshot) {
                        if (snapshot.hasData) {
                          _mealItem.ingredient = snapshot.data!;
                          return MealItemTile(
                            ingredient: _mealItem.ingredient,
                            nutritionalValues: _mealItem.nutritionalValues,
                          );
                        } else if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              'Ingredient lookup error: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        } else {
                          return const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ElevatedButton(
              key: const Key(SUBMIT_BUTTON_KEY_NAME),
              child: Text(AppLocalizations.of(context).save),
              onPressed: () async {
                if (!_form.currentState!.validate()) {
                  return;
                }
                _form.currentState!.save();
                _mealItem.ingredientId = int.parse(_ingredientIdController.text);

                try {
                  var date = DateTime.parse(_dateController.text);
                  final tod = stringToTime(_timeController.text);
                  date = DateTime(date.year, date.month, date.day, tod.hour, tod.minute);
                  widget.onSave(context, _mealItem, date);
                } on WgerHttpException catch (error) {
                  showHttpExceptionErrorDialog(error, context);
                } catch (error) {
                  showErrorDialog(error, context);
                }
                Navigator.of(context).pop();
              },
            ),
            if (suggestions.isNotEmpty) const SizedBox(height: 10.0),
            Container(
              padding: const EdgeInsets.all(10.0),
              child: Text(AppLocalizations.of(context).recentlyUsedIngredients),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: suggestions.length,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  return Card(
                    child: ListTile(
                      onTap: () {
                        final ingredient = suggestions[index].ingredient;
                        selectIngredient(ingredient.id, ingredient.name, suggestions[index].amount);
                      },
                      title: Text(
                          '${suggestions[index].ingredient.name} (${suggestions[index].amount.toStringAsFixed(0)}$unit)'),
                      subtitle: Text(getShortNutritionValues(
                          suggestions[index].ingredient.nutritionalValues, context)),
                      trailing: const Icon(Icons.copy),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}

class PlanForm extends StatefulWidget {
  late NutritionalPlan _plan;

  PlanForm([NutritionalPlan? plan]) {
    _plan = plan ?? NutritionalPlan.empty();
  }

  @override
  State<PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<PlanForm> {
  final _form = GlobalKey<FormState>();

  bool _onlyLogging = true;
  bool _addGoals = false;

  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _onlyLogging = widget._plan.onlyLogging;
    _addGoals = widget._plan.hasAnyGoals;
    _descriptionController.text = widget._plan.description;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ListView(
        children: [
          // Description
          TextFormField(
            key: const Key('field-description'),
            decoration: InputDecoration(labelText: AppLocalizations.of(context).description),
            controller: _descriptionController,
            onFieldSubmitted: (_) {},
            onSaved: (newValue) {
              widget._plan.description = newValue!;
            },
          ),
          SwitchListTile(
            title: Text(AppLocalizations.of(context).onlyLogging),
            subtitle: Text(AppLocalizations.of(context).onlyLoggingHelpText),
            value: _onlyLogging,
            onChanged: (value) {
              setState(() {
                _onlyLogging = !_onlyLogging;
              });
              widget._plan.onlyLogging = value;
            },
          ),
          SwitchListTile(
            title: Text(AppLocalizations.of(context).addGoalsToPlan),
            subtitle: Text(AppLocalizations.of(context).addGoalsToPlanHelpText),
            value: _addGoals,
            onChanged: (value) {
              setState(() {
                _addGoals = !_addGoals;
              });
              if (!value) {
                widget._plan.goalEnergy = null;
                widget._plan.goalProtein = null;
                widget._plan.goalCarbohydrates = null;
                widget._plan.goalFat = null;
              }
            },
          ),
          if (_addGoals)
            Column(
              children: [
                GoalMacros(
                  val: widget._plan.goalEnergy?.toString(),
                  label: AppLocalizations.of(context).goalEnergy,
                  suffix: AppLocalizations.of(context).kcal,
                  onSave: (double value) => widget._plan.goalEnergy = value,
                  key: const Key('field-goal-energy'),
                ),
                GoalMacros(
                  val: widget._plan.goalProtein?.toString(),
                  label: AppLocalizations.of(context).goalProtein,
                  suffix: AppLocalizations.of(context).g,
                  onSave: (double value) => widget._plan.goalProtein = value,
                  key: const Key('field-goal-protein'),
                ),
                GoalMacros(
                  val: widget._plan.goalCarbohydrates?.toString(),
                  label: AppLocalizations.of(context).goalCarbohydrates,
                  suffix: AppLocalizations.of(context).g,
                  onSave: (double value) => widget._plan.goalCarbohydrates = value,
                  key: const Key('field-goal-carbohydrates'),
                ),
                GoalMacros(
                  val: widget._plan.goalFat?.toString(),
                  label: AppLocalizations.of(context).goalFat,
                  suffix: AppLocalizations.of(context).g,
                  onSave: (double value) => widget._plan.goalFat = value,
                  key: const Key('field-goal-fat'),
                ),
              ],
            ),

          ElevatedButton(
            key: const Key(SUBMIT_BUTTON_KEY_NAME),
            child: Text(AppLocalizations.of(context).save),
            onPressed: () async {
              // Validate and save the current values to the plan
              final isValid = _form.currentState!.validate();
              if (!isValid) {
                return;
              }
              _form.currentState!.save();

              // Save to DB
              try {
                if (widget._plan.id != null) {
                  await Provider.of<NutritionPlansProvider>(context, listen: false)
                      .editPlan(widget._plan);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                } else {
                  widget._plan = await Provider.of<NutritionPlansProvider>(context, listen: false)
                      .addPlan(widget._plan);
                  if (context.mounted) {
                    Navigator.of(context).pushReplacementNamed(
                      NutritionalPlanScreen.routeName,
                      arguments: widget._plan,
                    );
                  }
                }

                // Saving was successful, reset the data
                _descriptionController.clear();
              } on WgerHttpException catch (error) {
                if (context.mounted) {
                  showHttpExceptionErrorDialog(error, context);
                }
              } catch (error) {
                if (context.mounted) {
                  showErrorDialog(error, context);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class GoalMacros extends StatelessWidget {
  const GoalMacros({
    super.key,
    required this.label,
    required this.suffix,
    required this.onSave,
    this.val,
  });

  final String label;
  final String suffix;
  final Function onSave;
  final String? val;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: val ?? '',
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
      ),
      keyboardType: TextInputType.number,
      onSaved: (newValue) {
        if (newValue == null || newValue == '') {
          return;
        }
        onSave(double.parse(newValue));
      },
      validator: (value) {
        if (value == '') {
          return null;
        }
        try {
          double.parse(value!);
        } catch (error) {
          return AppLocalizations.of(context).enterValidNumber;
        }
        return null;
      },
    );
  }
}

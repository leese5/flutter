import 'package:flutter/foundation.dart';
import 'package:wger/models/exercises/exercise.dart';

class Set {
  final int id;
  final int sets;
  final int order;
  List<Exercise> exercises = [];

  Set({
    @required this.id,
    @required this.sets,
    @required this.order,
    this.exercises,
  });
}
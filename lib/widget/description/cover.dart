import 'package:flutter/cupertino.dart';
import 'package:mc_mod_helper/model/mod.dart';

abstract class ModCard extends StatelessWidget {
  const ModCard({super.key, required this.mod});

  final ModSummary mod;
}

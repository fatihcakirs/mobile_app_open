import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/material.dart' hide Icons;

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:device_info/device_info.dart';
import 'package:flutter_svg/svg.dart';
import 'package:ios_utsname_ext/extension.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock/wakelock.dart';

import 'package:mlcommons_ios_app/backend/bridge.dart';
import 'package:mlcommons_ios_app/backend/native.dart';
import 'package:mlcommons_ios_app/benchmark/benchmark_result.dart';
import 'package:mlcommons_ios_app/benchmark/resource_manager.dart';
import 'package:mlcommons_ios_app/icons.dart';
import 'package:mlcommons_ios_app/info.dart';
import 'package:mlcommons_ios_app/localizations/app_localizations.dart';
import 'package:mlcommons_ios_app/protos/backend_setting.pb.dart' as pb;
import 'package:mlcommons_ios_app/protos/mlperf_task.pb.dart' as pb;
import 'package:mlcommons_ios_app/store.dart';

class Benchmark {
  final pb.BenchmarkSetting benchmarkSetting;
  final pb.TaskConfig taskConfig;
  final pb.ModelConfig modelConfig;

  double? score;
  String? accuracy;

  Benchmark(this.benchmarkSetting, this.taskConfig, this.modelConfig);

  String get id => modelConfig.id;

  String get name => modelConfig.name;

  double get maxScore => MAX_SCORE[id]!;

  /// 'Object Detection', 'Image Classification (offline)', and so on.
  String get taskName => taskConfig.name;

  /// 'IC', 'OD', and so on.
  String get code => modelConfig.id.split('_').first;

  /// 'SingleStream' or 'Offline'.
  String get scenario => modelConfig.scenario;

  SvgPicture get icon => BENCHMARK_ICONS[scenario]?[code] ?? Icons.logo;

  SvgPicture get iconWhite =>
      BENCHMARK_ICONS_WHITE[scenario]?[code] ?? Icons.logo;

  @override
  String toString() => 'Benchmark:$id';
}

class MiddleInterface {
  final List<Benchmark> benchmarks;
  final List<pb.Setting> commonSettings;
  final String backendLibPath;

  MiddleInterface._(this.benchmarks, this.commonSettings, this.backendLibPath);

  static Future<MapEntry<pb.BackendSetting, String>>
      findMatchingBackend() async {
    for (var backendPath in getBackendsList()) {
      if (Platform.isWindows) {
        backendPath = './backends/$backendPath';
      } else if (Platform.isAndroid) {
        backendPath = '$backendPath.so';
      }
      final backendSetting = await backendMatch(backendPath);
      if (backendSetting != null) {
        return MapEntry(backendSetting, backendPath);
      }
    }
    throw 'no matching backend found';
  }

  static Future<MiddleInterface> create(File configFile) async {
    final tasks = getMLPerfConfig(await configFile.readAsString());
    final backendMatchInfo = await findMatchingBackend();
    final backendSetting = backendMatchInfo.key;
    final backendPath = backendMatchInfo.value;

    final benchmarks = <Benchmark>[];
    for (final task in tasks.task) {
      for (final model in task.model) {
        final benchmarkSetting = backendSetting.benchmarkSetting
            .singleWhereOrNull((setting) => setting.benchmarkId == model.id);
        if (benchmarkSetting == null) continue;

        benchmarks.add(Benchmark(benchmarkSetting, task, model));
      }
    }

    return MiddleInterface._(
        benchmarks, backendSetting.commonSetting, backendPath);
  }

  /// The list of URL or file names to download.
  List<String> data() {
    final result = <String>[];

    for (final b in benchmarks) {
      result.add(b.taskConfig.liteDataset.path);
      result.add(b.taskConfig.liteDataset.groundtruthSrc);

      result.add(b.taskConfig.dataset.path);
      result.add(b.taskConfig.dataset.groundtruthSrc);

      result.add(b.taskConfig.testDataset.path);
      result.add(b.taskConfig.testDataset.groundtruthSrc);

      result.add(b.benchmarkSetting.src);
    }

    result.sort();
    return result.where((element) => element.isNotEmpty).toList();
  }
}

enum BenchmarkStateEnum {
  downloading,
  cooldown,
  waiting,
  running,
  aborting,
  done,
}

class BenchmarksConfiguration {
  final String name;
  final String path;

  BenchmarksConfiguration(this.name, this.path);

  String getType(AppLocalizations stringResources) => isInternetResource(path)
      ? stringResources.internetResource
      : stringResources.localResource;
}

class BenchmarkState extends ChangeNotifier {
  final Store _store;
  final BackendBridge backendBridge;

  late final ResourceManager resourceManager;

  String _chosenBenchmarksConfigurationName;
  // null - downloading/waiting; false - running; true - done
  bool? _doneRunning;
  bool _cooling = false;

  // Only if [state] == [BenchmarkStateEnum.downloading]
  String get downloadingProgress => resourceManager.progress;

  Future<BenchmarksConfiguration?> get chosenBenchmarksConfiguration async =>
      await resourceManager
          .getChosenConfiguration(_chosenBenchmarksConfigurationName);

  // Only if [state] == [BenchmarkStateEnum.running]
  Benchmark? currentlyRunning;
  String runningProgress = '';

  num get result {
    final benchmarksCount =
        benchmarks.where((benchmark) => benchmark.score != null).length;

    if (benchmarksCount == 0) return 0;

    final summaryScore = pow(
        benchmarks.fold<double>(1, (prev, i) {
          if (i.score != null) return prev * i.score!;
          return prev;
        }),
        1.0 / benchmarksCount);

    return summaryScore / _getSummaryMaxScore();
  }

  List<Benchmark> get benchmarks => _middle.benchmarks;

  // Settings from store
  bool _submissionMode = false;
  bool _testMode = false;
  bool _cooldown = false;
  int _cooldownPause = 0;
  Future<void> _cooldownFuture = Future.value();

  static const _fast = bool.fromEnvironment('fast-mode', defaultValue: false);

  bool _aborting = false;

  late MiddleInterface _middle;

  BenchmarkState._(this._store, this.backendBridge)
      : _chosenBenchmarksConfigurationName = _store.chosenConfigurationName {
    resourceManager = ResourceManager(notifyListeners);
  }

  static double _getSummaryMaxScore() => MAX_SCORE['SUMMARY_MAX_SCORE']!;

  Future<String> validateExternalResourcesDirectory(
      String errorDescription) async {
    final datasetsError = <String>[];

    for (final job in _getBenchmarkJobs()) {
      final dataset = job.dataset;
      final groundTruthSrc = dataset.groundtruthSrc;

      if (!await resourceManager.isResourceExist(dataset.path) ||
          (!await resourceManager.isResourceExist(groundTruthSrc)) &&
              _store.submissionMode) {
        final error = dataset.type.name;
        if (!datasetsError.contains(error)) {
          datasetsError.add('$error');
        }
      }
    }

    if (datasetsError.isEmpty) return '';

    var index = 0;
    return errorDescription +
        datasetsError.map((element) => '\n${++index}) $element').join();
  }

  Future<void> loadResources(File configFile) async {
    _middle = await MiddleInterface.create(configFile);
    for (final item in _middle.benchmarks) {
      BatchPreset? batchPreset;
      if (item.modelConfig.scenario == 'Offline') {
        var presetList = resourceManager.getBatchPresets();

        if (Platform.isIOS) {
          var iosInfo = await DeviceInfoPlugin().iosInfo;
          final currentDevice = iosInfo.utsname.machine.iOSProductName;
          for (var p in presetList) {
            if (currentDevice.startsWith(p.name)) {
              batchPreset = p;
              break;
            }
          }
        }
        batchPreset ??= presetList[0];
      }

      _store.addBenchmarkToList(item.id, item.taskName, batchPreset);
    }
    resourceManager.resources = _middle.data();
    await reset();

    final packageInfo = await PackageInfo.fromPlatform();
    final newAppVersion = packageInfo.version + '+' + packageInfo.buildNumber;
    var needToPurgeCache = false;
    if (_store.previousAppVersion != newAppVersion) {
      _store.previousAppVersion = newAppVersion;
      needToPurgeCache = true;
    }
    resourceManager.handleResources(needToPurgeCache);
  }

  Future<bool> _handlePreviousResult() async {
    if (_doneRunning == null) {
      final content = _store.previousResult;

      if (content.isNotEmpty) {
        try {
          for (final resultContent in jsonDecode(content)) {
            final result = resultContent as Map<String, dynamic>;
            final id = result['benchmark_id'] as String;
            final accuracy = result['accuracy'] as String?;
            final score = result['score'] as double?;
            final threadsNumber = result['shards_num'] as int?;
            final batchSize = result['batch_size'] as int?;
            final benchmark =
                benchmarks.singleWhere((benchmark) => benchmark.id == id);
            benchmark.accuracy = accuracy;
            benchmark.score = score;

            if (benchmark.modelConfig.scenario == 'Offline') {
              benchmark.benchmarkSetting.customSetting.add(pb.CustomSetting(
                  id: 'batch_size', value: batchSize.toString()));
              benchmark.benchmarkSetting.customSetting.add(pb.CustomSetting(
                  id: 'shards_num', value: threadsNumber.toString()));
              benchmark.benchmarkSetting.writeToBuffer();
            }
          }
        } catch (_) {
          return false;
        }
        return true;
      }
    } else {
      await _store.deletePreviousResult();
      await resourceManager.deleteResultJson();
    }

    return false;
  }

  static Future<BenchmarkState> create(Store store) async {
    final result = BenchmarkState._(store, await BackendBridge.create());

    await result.resourceManager.initSystemPaths();
    await result.resourceManager.loadBatchPresets();
    final configFile = await result.handleChosenConfiguration(store: store);
    await result.loadResources(configFile!);

    final loadFromStore = () {
      result._submissionMode = store.submissionMode;
      result._testMode = store.testMode;
      result._cooldown = store.cooldown;
      result._cooldownPause = store.cooldownPause;
    };
    store.addListener(loadFromStore);
    loadFromStore();
    return result;
  }

  Future<File?> handleChosenConfiguration(
      {BenchmarksConfiguration? newChosenConfiguration,
      required Store store}) async {
    final benchmarksConfiguration = newChosenConfiguration ??
        await resourceManager
            .getChosenConfiguration(_chosenBenchmarksConfigurationName);
    final path = benchmarksConfiguration?.path ??
        resourceManager.defaultBenchmarksConfiguration.path;
    final configurationName = benchmarksConfiguration?.name ??
        resourceManager.defaultBenchmarksConfiguration.name;
    File configFile;

    if (isInternetResource(path)) {
      try {
        final baseName = path.split('/').last;
        final currentConfigFile =
            File('${resourceManager.applicationDirectory}/$baseName');

        if (newChosenConfiguration != null ||
            benchmarksConfiguration == null ||
            !await currentConfigFile.exists()) {
          configFile = await resourceManager.getFileByUrl(path);
          configFile = await resourceManager.moveFile(
              configFile, currentConfigFile.path);
        } else {
          configFile = currentConfigFile;
        }
      } catch (e) {
        print(e);
        return null;
      }
    } else {
      configFile = File('${resourceManager.externalResourcesDir}/$path');

      if (!await configFile.exists()) return null;
    }

    if (newChosenConfiguration != null || benchmarksConfiguration == null) {
      _chosenBenchmarksConfigurationName = configurationName;
      store.chosenConfigurationName = configurationName;

      final nonRemovableResources = <String>[configFile.path];

      await resourceManager.deleteLoadedResources(nonRemovableResources);
    }

    return configFile;
  }

  BenchmarkStateEnum get state {
    if (!resourceManager.done) return BenchmarkStateEnum.downloading;
    switch (_doneRunning) {
      case null:
        return BenchmarkStateEnum.waiting;
      case false:
        return _aborting
            ? BenchmarkStateEnum.aborting
            : _cooling
                ? BenchmarkStateEnum.cooldown
                : BenchmarkStateEnum.running;
      case true:
        return BenchmarkStateEnum.done;
    }
    throw StateError('unreachable');
  }

  List<BenchmarkJob> _getBenchmarkJobs() {
    final submissionMode = _submissionMode;
    final testMode = _testMode;
    final jobs = <BenchmarkJob>[];

    for (final benchmark in _middle.benchmarks) {
      var storedConfig = _store
          .getBenchmarkList()
          .firstWhere((element) => element.id == benchmark.id);
      if (!storedConfig.active) continue;
      benchmark.benchmarkSetting.batchSize = storedConfig.batchSize;
      jobs.add(BenchmarkJob(
        benchmark,
        testMode
            ? benchmark.taskConfig.testDataset
            : benchmark.taskConfig.liteDataset,
        testMode ? DatasetMode.test : DatasetMode.lite,
        false,
        testMode ? true : _fast,
        storedConfig.threadsNumber,
        backendBridge,
        _middle.backendLibPath,
      ));

      if (!submissionMode) continue;

      jobs.add(BenchmarkJob(
        benchmark,
        benchmark.taskConfig.dataset,
        DatasetMode.full,
        true,
        _fast,
        storedConfig.threadsNumber,
        backendBridge,
        _middle.backendLibPath,
      ));
    }
    return jobs;
  }

  void runBenchmarks() async {
    await reset();

    assert(resourceManager.done, 'Resource manager is not done.');
    assert(_doneRunning == null, '_doneRunning is not null');
    _doneRunning = false;

    // disable screen sleep when benchmarks is running
    await Wakelock.enable();

    final cooldown = _cooldown;
    final cooldownPause = _cooldownPause;
    final jobs = _getBenchmarkJobs();

    var n = 0;
    var wasAccuracy = true;
    final results = <RunResult?>[];

    for (final job in jobs) {
      if (_aborting) break;

      if (cooldown && !job.accuracy && !wasAccuracy) {
        _cooling = true;
        notifyListeners();
        await (_cooldownFuture = Future.delayed(
            _fast ? Duration(seconds: 1) : Duration(minutes: cooldownPause)));
        _cooling = false;
        notifyListeners();
      }
      if (_aborting) break;
      wasAccuracy = job.accuracy;

      final resultFuture = job._run(resourceManager, _middle.commonSettings);
      currentlyRunning = job.benchmark;
      runningProgress = '${(100 * (n++ / jobs.length)).round()}%';
      notifyListeners();

      final result = await resultFuture;
      results.add(result);

      if (job.accuracy) {
        job.benchmark.accuracy = result?.accuracy;
      } else {
        job.benchmark.score = result?.score;
      }
    }

    if (!_aborting) await _recordResult(results);

    currentlyRunning = null;
    _doneRunning = _aborting ? null : true;
    _aborting = false;
    notifyListeners();

    await Wakelock.disable();
  }

  Future<void> _recordResult(List<RunResult?> results) async {
    final resultContent = <Map<String, dynamic>>[];
    final briefResultContent = <Map<String, dynamic>>[];

    for (final result in results) {
      if (result != null) {
        final score =
            result.mode == BenchmarkMode.accuracy ? null : result.score;

        final benchmarkResult = {
          'benchmark_id': result.id,
          'configuration': {
            'runtime': '',
          },
          'score': score != null ? score.toString() : 'N/A',
          'accuracy': BenchmarkMode.performance_lite == result.mode
              ? 'N/A'
              : result.accuracy,
          // strings are used here to match android app behavior
          'min_duration': result.minDuration.toString(),
          'duration': result.durationMs.toString(),
          'min_samples': result.minSamples.toString(),
          'num_samples': result.numSamples.toString(),
          'shards_num': result.threadsNumber,
          'batch_size': result.batchSize,
          'mode': result.mode.toString(),
          'datetime': DateTime.now().toIso8601String(),
        };
        final benchmarkBriefResult = {
          'benchmark_id': result.id,
          'score': score,
          'accuracy': result.accuracy,
          'shards_num': result.threadsNumber,
          'batch_size': result.batchSize,
        };

        resultContent.add(benchmarkResult);
        briefResultContent.add(benchmarkBriefResult);
      }
    }

    _store.previousResult = JsonEncoder().convert(briefResultContent);
    await resourceManager.writeToJsonResult(resultContent);
  }

  Future<void> abortBenchmarks() async {
    if (_doneRunning == false) {
      _aborting = true;
      await CancelableOperation.fromFuture(_cooldownFuture).cancel();
      notifyListeners();
    }
  }

  Future<void> reset() async {
    final isPreviousResultUsed = await _handlePreviousResult();

    if (isPreviousResultUsed) {
      _doneRunning = true;
    } else {
      _middle.benchmarks
          .forEach((benchmark) => benchmark.accuracy = benchmark.score = null);
      _doneRunning = null;
    }

    _aborting = false;
  }
}

enum DatasetMode { lite, full, test }

class BenchmarkJob {
  final Benchmark benchmark;
  final pb.DatasetConfig dataset;
  final bool accuracy;
  final bool fast;
  final DatasetMode _datasetMode;
  final int threadsNumber;
  final BackendBridge backend;
  final String backendLibPath;

  BenchmarkJob(
    this.benchmark,
    this.dataset,
    this._datasetMode,
    this.accuracy,
    this.fast,
    this.threadsNumber,
    this.backend,
    this.backendLibPath,
  );

  Future<RunResult?> _run(
      ResourceManager resourceManager, List<pb.Setting> commonSettings) async {
    final tmpDir = await getTemporaryDirectory();

    print(
        'Running $benchmark in ${accuracy ? 'accuracy' : 'performance'} mode...');
    final stopwatch = Stopwatch()..start();

    var minQueryCount = fast ? 8 : benchmark.taskConfig.minQueryCount;
    var minDuration = fast ? 10 : benchmark.taskConfig.minDurationMs;

    final settings = pb.SettingList(
      setting: commonSettings,
      benchmarkSetting: benchmark.benchmarkSetting,
    );

    final batchSizeValue = benchmark.benchmarkSetting.batchSize;

    if (benchmark.modelConfig.scenario == 'Offline') {
      var shardsNumSetting = benchmark.benchmarkSetting.customSetting
          .singleWhereOrNull((element) => element.id == 'shards_num');
      if (shardsNumSetting == null) {
        benchmark.benchmarkSetting.customSetting.add(pb.CustomSetting(
            id: 'shards_num', value: threadsNumber.toString()));
      } else {
        shardsNumSetting.value = threadsNumber.toString();
      }
      var batchSizeSetting = benchmark.benchmarkSetting.customSetting
          .singleWhereOrNull((element) => element.id == 'batch_size');
      if (batchSizeSetting == null) {
        benchmark.benchmarkSetting.customSetting.add(pb.CustomSetting(
            id: 'batch_size', value: batchSizeValue.toString()));
      } else {
        batchSizeSetting.value = batchSizeValue.toString();
      }

      benchmark.benchmarkSetting.batchSize *= threadsNumber;
      settings.setting.add(pb.Setting(
        id: 'shards_num',
        name: 'Number of threads for inference',
        value: pb.Setting_Value(
          name: threadsNumber.toString(),
          value: threadsNumber.toString(),
        ),
      ));
    }

    final result = await backend.run(RunSettings(
      backend_model_path: resourceManager.get(benchmark.benchmarkSetting.src),
      backend_lib_path: backendLibPath,
      backend_settings: settings.writeToBuffer(),
      backend_native_lib_path: '' /* TFLite backend ignores this*/,
      dataset_type: benchmark.taskConfig.dataset.type.value,
      dataset_data_path: resourceManager.get(dataset.path),
      dataset_groundtruth_path: resourceManager.get(dataset.groundtruthSrc),
      dataset_offset: benchmark.modelConfig.offset,
      scenario: benchmark.modelConfig.scenario,
      batch: benchmark.benchmarkSetting.batchSize,
      batch_size: batchSizeValue,
      threads_number: threadsNumber,
      mode: accuracy
          ? BenchmarkMode.backendAccuracy
          : BenchmarkMode.backendPerfomance,
      min_query_count: minQueryCount,
      min_duration: minDuration,
      output_dir: tmpDir.path,
      benchmark_id: benchmark.id,
      dataset_mode: _datasetMode,
    ));
    final elapsed = stopwatch.elapsed;

    print('Benchmark result: $result, elapsed: $elapsed');
    return result;
  }
}

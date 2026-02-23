import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/esp32_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    context.read<Esp32Service>().fetchStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('智能人脸枕头'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showIpSettings(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusPanel(context),
            const SizedBox(height: 24),
            _buildFaceEnrollSection(context),
            const SizedBox(height: 24),
            _buildLiquidLevelSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPanel(BuildContext context) {
    return Consumer<Esp32Service>(
      builder: (_, svc, __) {
        final s = svc.status;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('参数显示', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (svc.error != null)
                  Text(svc.error!, style: const TextStyle(color: Colors.red)),
                if (s != null) ...[
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          svc.captureUrl,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey[300],
                            child: const Icon(Icons.face, size: 40),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('人脸: ${s.faceName.isEmpty ? "未识别" : s.faceName}'),
                            Text('设定液面: ${s.setLevelCm.toStringAsFixed(1)} cm'),
                            Text('当前液面: ${s.currentLevelCm.toStringAsFixed(1)} cm'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else if (svc.error == null)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFaceEnrollSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('人脸录入', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _onEnrollNew(context),
                    icon: const Icon(Icons.person_add),
                    label: const Text('1. 录入新用户'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _onConfirmEnroll(context),
                    icon: const Icon(Icons.check),
                    label: const Text('2. 确定录入'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _onDeleteFace(context),
                    icon: const Icon(Icons.delete),
                    label: const Text('3. 删除'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiquidLevelSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('液面高度设定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _onLiquidLevelSetting(context),
                icon: const Icon(Icons.water_drop),
                label: const Text('液面高度设定'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onEnrollNew(BuildContext context) async {
    final svc = context.read<Esp32Service>();
    final result = await svc.enrollNewUser();
    if (!context.mounted) return;
    if (result != null) {
      final id = result['id'] as int;
      _showNameDialog(context, id, result['name'] as String? ?? '用户');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('录入失败: ${svc.error}')),
      );
    }
  }

  void _showNameDialog(BuildContext context, int id, String initialName) {
    final controller = TextEditingController(text: initialName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定录入人脸ID'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '人脸命名',
            hintText: '请输入名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim().isEmpty ? '用户' : controller.text.trim();
              Navigator.pop(ctx);
              final ok = await context.read<Esp32Service>().confirmEnroll(id, name);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ok ? '录入成功' : '录入失败')),
              );
            },
            child: const Text('确定录入'),
          ),
        ],
      ),
    );
  }

  Future<void> _onConfirmEnroll(BuildContext context) async {
    final svc = context.read<Esp32Service>();
    await svc.fetchFaces();
    if (!context.mounted) return;
    if (svc.faces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先录入新用户')),
      );
      return;
    }
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => _FaceSelectDialog(faces: svc.faces),
    );
    if (selected == null || !context.mounted) return;
    final face = svc.faces.firstWhere((f) => f.id == selected);
    _showNameDialog(context, face.id, face.name);
  }

  Future<void> _onDeleteFace(BuildContext context) async {
    final svc = context.read<Esp32Service>();
    await svc.fetchFaces();
    if (!context.mounted) return;
    if (svc.faces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可删除的人脸')),
      );
      return;
    }
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => _FaceSelectDialog(faces: svc.faces, title: '选择要删除的人脸'),
    );
    if (selected == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除该人脸吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await svc.deleteFace(selected);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '删除成功' : '删除失败')),
    );
  }

  Future<void> _onLiquidLevelSetting(BuildContext context) async {
    final svc = context.read<Esp32Service>();
    await svc.fetchFaces();
    if (!context.mounted) return;
    if (svc.faces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先录入人脸')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _LiquidLevelSheet(faces: svc.faces),
    );
  }

  void _showIpSettings(BuildContext context) {
    final svc = context.read<Esp32Service>();
    final controller = TextEditingController(text: svc.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ESP32 地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            hintText: 'http://192.168.4.1',
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              await svc.setBaseUrl(controller.text);
              if (!context.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _FaceSelectDialog extends StatelessWidget {
  final List<FaceRecord> faces;
  final String? title;

  const _FaceSelectDialog({required this.faces, this.title});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title ?? '选择人脸'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: faces.length,
          itemBuilder: (_, i) {
            final f = faces[i];
            return ListTile(
              title: Text(f.name),
              subtitle: Text('ID: ${f.id}, 液面: ${f.liquidLevelCm.toStringAsFixed(1)} cm'),
              onTap: () => Navigator.pop(context, f.id),
            );
          },
        ),
      ),
    );
  }
}

class _LiquidLevelSheet extends StatefulWidget {
  final List<FaceRecord> faces;

  const _LiquidLevelSheet({required this.faces});

  @override
  State<_LiquidLevelSheet> createState() => _LiquidLevelSheetState();
}

class _LiquidLevelSheetState extends State<_LiquidLevelSheet> {
  late int _selectedFaceId;
  late double _levelCm;
  late FixedExtentScrollController _faceController;
  late FixedExtentScrollController _levelController;

  @override
  void initState() {
    super.initState();
    _selectedFaceId = widget.faces.first.id;
    _levelCm = widget.faces.first.liquidLevelCm;
    _faceController = FixedExtentScrollController();
    _levelController = FixedExtentScrollController();
  }

  @override
  void dispose() {
    _faceController.dispose();
    _levelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('1号轮盘 - 选择人脸', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListWheelScrollView.useDelegate(
                controller: _faceController,
                itemExtent: 48,
                diameterRatio: 1.5,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) {
                  setState(() {
                    _selectedFaceId = widget.faces[i].id;
                    _levelCm = widget.faces[i].liquidLevelCm;
                  });
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: widget.faces.length,
                  builder: (_, i) {
                    final f = widget.faces[i];
                    final sel = f.id == _selectedFaceId;
                    return Center(
                      child: Text(
                        '${f.name} (${f.liquidLevelCm.toStringAsFixed(1)} cm)',
                        style: TextStyle(
                          fontSize: sel ? 18 : 14,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('2号轮盘 - 液面高度 (5~15 cm)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListWheelScrollView.useDelegate(
                controller: _levelController,
                itemExtent: 48,
                diameterRatio: 1.5,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) {
                  setState(() => _levelCm = 5.0 + i);
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: 11,
                  builder: (_, i) {
                    final v = 5.0 + i;
                    final sel = (v - _levelCm).abs() < 0.1;
                    return Center(
                      child: Text(
                        '${v.toStringAsFixed(1)} cm',
                        style: TextStyle(
                          fontSize: sel ? 18 : 14,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Slider(
              value: _levelCm,
              min: 5,
              max: 15,
              divisions: 100,
              label: '${_levelCm.toStringAsFixed(1)} cm',
              onChanged: (v) => setState(() => _levelCm = v),
            ),
            Text('当前选定: ${_levelCm.toStringAsFixed(1)} cm', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final ok = await context.read<Esp32Service>().setLiquidLevel(_selectedFaceId, _levelCm);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? '液面设定已保存' : '保存失败')),
                );
              },
              child: const Text('确定录入液面高度'),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/pages/assinatura_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../utils/colors.dart'; // usa as cores do app

class AssinaturaPage extends StatefulWidget {
  /// PNG opcional para pré-visualização (assinatura já existente)
  final Uint8List? assinatura;
  const AssinaturaPage({Key? key, this.assinatura}) : super(key: key);

  @override
  State<AssinaturaPage> createState() => _AssinaturaPageState();
}

class _AssinaturaPageState extends State<AssinaturaPage> {
  late final SignatureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3.2,
      penColor: Colors.black87,
      // exporta com traço preto e fundo transparente (ideal p/ PDF)
      exportPenColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _salvarAssinatura() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assinatura em branco!')),
      );
      return;
    }

    // Exporta PNG. Em algumas versões, não há parâmetro de pixelRatio;
    // usamos um canvas MAIOR na tela para aumentar a nitidez.
    final Uint8List? bytes = await _controller.toPngBytes();
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assine dentro do quadro.')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, bytes); // devolve a assinatura (Uint8List PNG)
  }

  void _limparAssinatura() {
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo_circular.png',
              height: 30,
              errorBuilder: (_, __, ___) => const SizedBox(height: 30, width: 30),
            ),
            const SizedBox(width: 12),
            const Text(
              'Assinatura',
              style: TextStyle(
                color: milkdimOrange,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'Assine dentro do quadro abaixo:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: milkdimOrange,
                  ),
                ),
                const SizedBox(height: 20),

                // Preview opcional se já existir assinatura salva
                if (widget.assinatura != null) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Assinatura atual:',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      widget.assinatura!,
                      height: 70,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // QUADRO DE ASSINATURA — MAIOR E RESPONSIVO
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Deixa bem grande: ~40% da largura (mín. 200, máx. 340 px de altura)
                    final double h =
                    (constraints.maxWidth * 0.40).clamp(200.0, 340.0);
                    return SizedBox(
                      height: h,
                      width: double.infinity,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: milkdimOrange, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Signature(
                            controller: _controller,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _limparAssinatura,
                      icon: const Icon(Icons.clear, color: Colors.red),
                      label: const Text('Limpar', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 24,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _salvarAssinatura,
                      icon: const Icon(Icons.check),
                      label: const Text('Salvar Assinatura'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: milkdimOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 24,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

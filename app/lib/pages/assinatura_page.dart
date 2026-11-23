// lib/pages/assinatura_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:signature/signature.dart';

class AssinaturaPage extends StatefulWidget {
  /// PNG opcional para pré-visualização (assinatura já existente)
  final Uint8List? assinatura;

  /// Título da barra: "Assinatura do pedido" ou "Assinatura da entrega".
  final String titulo;

  /// Por que o cliente precisa assinar (ex.: "O cliente precisa assinar o
  /// pedido."); null não mostra a faixa.
  final String? aviso;

  const AssinaturaPage({Key? key, this.assinatura, this.titulo = 'Assinatura', this.aviso})
      : super(key: key);

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
      showMdSnack(context, 'Assinatura em branco!', tipo: MdTipo.atencao);
      return;
    }

    // Exporta PNG. Em algumas versões, não há parâmetro de pixelRatio;
    // usamos um canvas MAIOR na tela para aumentar a nitidez.
    final Uint8List? bytes = await _controller.toPngBytes();
    if (bytes == null || bytes.isEmpty) {
      showMdSnack(context, 'Assine dentro do quadro.', tipo: MdTipo.atencao);
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
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MdSpace.lg),
          child: MdContentWidth(
            maxWidth: 840,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.aviso != null) ...[
                  MdBanner(
                    tipo: MdTipo.atencao,
                    texto: widget.aviso!,
                    icone: Icons.draw_outlined,
                  ),
                  const SizedBox(height: MdSpace.lg),
                ],
                MdCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Assine dentro do quadro abaixo:', style: tt.titleMedium),
                      const SizedBox(height: MdSpace.lg),

                      // Preview opcional se já existir assinatura salva
                      if (widget.assinatura != null) ...[
                        Text('Assinatura atual:', style: tt.bodySmall),
                        const SizedBox(height: MdSpace.xs),
                        Container(
                          height: 70,
                          padding: const EdgeInsets.all(MdSpace.xs),
                          decoration: BoxDecoration(
                            color: MdColors.background,
                            borderRadius: BorderRadius.circular(MdRadius.field),
                          ),
                          child: Image.memory(widget.assinatura!, fit: BoxFit.contain),
                        ),
                        const SizedBox(height: MdSpace.lg),
                      ],

                      // QUADRO DE ASSINATURA — MAIOR E RESPONSIVO
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Deixa bem grande: ~40% da largura (mín. 200, máx. 340 px de altura)
                          final double h = (constraints.maxWidth * 0.40).clamp(200.0, 340.0);
                          return Container(
                            height: h,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: MdColors.surface,
                              border: Border.all(color: MdColors.primary, width: 2),
                              borderRadius: BorderRadius.circular(MdRadius.field),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(MdRadius.field - 2),
                              child: Stack(
                                children: [
                                  // Linha-guia (só na tela; não entra no PNG exportado).
                                  Positioned(
                                    left: MdSpace.xl,
                                    right: MdSpace.xl,
                                    bottom: h * 0.25,
                                    child: Container(height: 1, color: MdColors.border),
                                  ),
                                  Positioned.fill(
                                    child: Signature(
                                      controller: _controller,
                                      backgroundColor: Colors.transparent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: MdSpace.lg),

                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _limparAssinatura,
                            icon: const Icon(Icons.clear),
                            label: const Text('Limpar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: MdColors.danger,
                              side: const BorderSide(color: MdColors.danger),
                              minimumSize: const Size(0, 52),
                              padding: const EdgeInsets.symmetric(horizontal: MdSpace.lg),
                            ),
                          ),
                          const SizedBox(width: MdSpace.md),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _salvarAssinatura,
                              icon: const Icon(Icons.check),
                              label: const Text('Salvar Assinatura'),
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

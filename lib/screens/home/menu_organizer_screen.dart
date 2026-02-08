import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:provider/provider.dart';

// Définition statique des métadonnées pour l'organisateur
class MenuMetadata {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  MenuMetadata(this.id, this.label, this.icon, this.color);
}

// Liste complète de tous les menus disponibles dans l'application
// INCLUT MAINTENANT VOS NOUVEAUX MENUS
final List<MenuMetadata> allMenuMetadata = [
  // --- Anciens Menus ---
  MenuMetadata('prevente', 'Pre/Vente', Icons.point_of_sale, Colors.blue.shade700),
  MenuMetadata('assurance', 'Pre/Vente Assurance', Icons.health_and_safety, Colors.red.shade700),
  MenuMetadata('carnet', 'Vente Carnet', Icons.book, Colors.green.shade800),
  MenuMetadata('caisse', 'Gestion Caisse', Icons.calculate, Colors.lime.shade700),
  MenuMetadata('perimes', 'Gestion Périmés', Icons.dangerous, Colors.deepOrange.shade600),
  MenuMetadata('evaluation', 'Évaluation Vente', Icons.bar_chart, Colors.green.shade700),
  MenuMetadata('search', 'Recherche Article', Icons.search, Colors.orange.shade700),
  MenuMetadata('update_perim', 'Mise à jour Péremption', Icons.date_range, Colors.purple.shade700),
  MenuMetadata('delivery', 'Contrôle Livraison', Icons.inventory_2, Colors.teal.shade700),
  MenuMetadata('bl_control', 'Pointage BL Stock', Icons.checklist, Colors.cyan.shade700),
  MenuMetadata('update_ean', 'Mise à jour EAN', Icons.qr_code_scanner, Colors.indigo.shade400),
  MenuMetadata('update_emplacement', 'Mise à jour Emplacement', Icons.location_on, Colors.brown.shade400),
  MenuMetadata('stock', 'État de Stock', Icons.inventory, Colors.blueGrey.shade600),

  // --- Nouveaux Menus ---
  MenuMetadata('depot', 'Vente Dépôt', Icons.store_mall_directory, Colors.brown.shade600),
  MenuMetadata('proforma', 'Proforma / Devis', Icons.description, Colors.purple.shade600),
  MenuMetadata('analyse_article', 'Analyse Article', Icons.analytics, Colors.blueGrey.shade700),
  MenuMetadata('ajustement', 'Ajustement Stock', Icons.inventory_2, Colors.orange.shade700),
];

class MenuOrganizerScreen extends StatefulWidget {
  const MenuOrganizerScreen({super.key});

  @override
  State<MenuOrganizerScreen> createState() => _MenuOrganizerScreenState();
}

class _MenuOrganizerScreenState extends State<MenuOrganizerScreen> {
  late List<MenuMetadata> _currentList;
  late Set<String> _hiddenIds;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    // 1. Récupérer l'ordre sauvegardé
    List<String> savedOrder = settings.menuOrder;
    _hiddenIds = settings.hiddenMenuIds.toSet();

    // 2. Construire la liste initiale
    _currentList = [];

    // D'abord ceux qui sont dans l'ordre sauvegardé
    for (var id in savedOrder) {
      try {
        var meta = allMenuMetadata.firstWhere((m) => m.id == id);
        _currentList.add(meta);
      } catch (e) {
        // ID obsolète, on ignore
      }
    }

    // Ensuite ajouter ceux qui manquent (les nouveaux menus)
    for (var meta in allMenuMetadata) {
      if (!_currentList.any((m) => m.id == meta.id)) {
        _currentList.add(meta);
      }
    }
  }

  void _save() {
    final newOrder = _currentList.map((m) => m.id).toList();
    Provider.of<SettingsProvider>(context, listen: false)
        .saveMenuConfig(newOrder, _hiddenIds.toList());

    Navigator.of(context).pop();
  }

  void _reset() {
    Provider.of<SettingsProvider>(context, listen: false).resetMenuConfig();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organiser le Menu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Rétablir défaut',
            onPressed: _reset,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Enregistrer',
            onPressed: _save,
          ),
        ],
      ),
      body: ReorderableListView(
        padding: const EdgeInsets.all(16),
        onReorder: (int oldIndex, int newIndex) {
          setState(() {
            if (oldIndex < newIndex) {
              newIndex -= 1;
            }
            final item = _currentList.removeAt(oldIndex);
            _currentList.insert(newIndex, item);
          });
        },
        children: [
          for (int index = 0; index < _currentList.length; index++)
            _buildListItem(_currentList[index], index)
        ],
      ),
    );
  }

  Widget _buildListItem(MenuMetadata meta, int index) {
    final isHidden = _hiddenIds.contains(meta.id);

    return Card(
      key: ValueKey(meta.id),
      elevation: 2,
      color: isHidden ? Colors.grey[200] : Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(meta.icon, color: isHidden ? Colors.grey : meta.color),
        title: Text(
          meta.label,
          style: TextStyle(
            color: isHidden ? Colors.grey : Colors.black87,
            decoration: isHidden ? TextDecoration.lineThrough : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bouton Oeil pour afficher/masquer
            IconButton(
              icon: Icon(isHidden ? Icons.visibility_off : Icons.visibility),
              color: isHidden ? Colors.grey : Colors.blue,
              onPressed: () {
                setState(() {
                  if (isHidden) {
                    _hiddenIds.remove(meta.id);
                  } else {
                    _hiddenIds.add(meta.id);
                  }
                });
              },
            ),
            // Poignée de déplacement
            const Icon(Icons.drag_handle, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
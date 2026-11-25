# Journal des versions — Photothèque pour iOS

## [0.2.0] — 2026-11-25

### Ajouté

- **Filtres à choix multiples** : années, appareils, formats et mots-clés (ou logique entre les valeurs d'un même critère), plus objectif, lieu, orientation, avec ou sans mot-clé. Écran Filtres dédié, effectif en direct.
- **Critères ET / OU** : toutes les conditions (par défaut) ou au moins une ; le texte saisi reste exigé. S'enregistre dans les recherches enregistrées ; les recherches de la version 0.1 restent lisibles.
- **Tableau de bord** : chiffres, graphiques par année et par mois, répartitions cliquables (formats, appareils, objectifs, notes, orientation), manques, plus gros fichiers, export CSV, sur tout le catalogue ou sur les photos affichées.
- **Rapports** : inventaire, fichiers manquants, intégrité, état des sauvegardes (alerte au-delà de 30 jours), photos à documenter ; export CSV et PDF.
- **À propos** : version installée, recherche de mise à jour sur GitHub (à la demande), téléchargement de l'.ipa avec vérification SHA-256.
- Onglet **Analyse** (tableau de bord, doublons, rapports).

### Modifié

- Les sauvegardes conservent les recherches enregistrées à plusieurs mots-clés (`keywordPaths`).

## [0.1.0] — 2026-11-08

Première version : application iOS autonome (iPhone / iPad, iOS 17+).

### Ajouté

- **Cœur `PhotothequeCore`** (Swift + SQLite, sans interface, testable sous Linux) :
  catalogue avec migrations et contrôle d'intégrité ; import par copie (originaux jamais
  modifiés), doublons exacts SHA-256, noms uniques ; mots-clés hiérarchiques, synonymes, fusion,
  doublons de vocabulaire ; recherche FTS5 insensible aux accents (repli LIKE) et critères ;
  collections et recherches enregistrées ; photos semblables (dHash) ; sauvegardes ZIP
  (catalogue seul ou complète), vérification CRC + SHA-256, restauration par fusion avec
  sauvegarde de sécurité ; catalogue CSV ; journal.
- **Application SwiftUI** : grille (3 tailles), recherche et filtres, sélection multiple et
  actions groupées, visionneuse (balayage, zoom), fiche photo, écrans Mots-clés, Collections,
  Doublons, Réglages (chiffres, sauvegardes, CSV, intégrité, cache, journal).
- Import depuis l'app Photos (fichier d'origine) et depuis Fichiers ; métadonnées par ImageIO.
- Dossier de l'app visible dans Fichiers (« Sur mon iPhone › Photothèque »).
- **Documentation** : compatibilité iOS (`docs/COMPATIBILITE.md`), installation
  (`docs/INSTALLATION-IOS.md`).
- **CI GitHub** : tests du cœur (Linux et macOS), compilation de l'app, lancement dans le
  simulateur avec import de photos d'essai, `.ipa` non signée ; publication sur tag `v*`.
- Tests du cœur sous Windows + WSL (`scripts/test-wsl.sh`).

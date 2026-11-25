# Journal des versions — Photothèque pour iOS

## [0.5.0] — 2026-11-25

Assistant local, sauvegardes chiffrées, métadonnées, variantes : reste des fonctions de la Photothèque de bureau qui ont un sens sur iOS.

### Ajouté

- **Sauvegardes** : chiffrement AES-256-GCM (clé dérivée du mot de passe par PBKDF2-HMAC-SHA256, 200 000 itérations, blocs authentifiés :
  un bloc déplacé, retiré ou une archive tronquée sont détectés), mot de passe gardé dans le trousseau de l'appareil ; planification
  (rappel ou sauvegarde automatique à l'ouverture), rotation des archives, copies vers des dossiers choisis dans Fichiers (iCloud Drive,
  disque, serveur), alertes (jamais sauvegardé, sauvegarde ancienne, photos non couvertes), **test de restauration** dans un catalogue
  temporaire (la seule preuve qu'une archive est utilisable), **restauration sélective** (métadonnées, mots-clés, collections, retouches,
  albums, photos absentes), verrouillage par Face ID / code de l'appareil.
- **Assistant IA local** (Vision d'Apple, sur l'appareil, aucune image n'en sort) : étiquettes des images, suggestions de mots-clés à
  valider une par une, recherche par description (français ou anglais), événements, lieux, photos proches.
- **Métadonnées** : modification en masse avec aperçu avant / après et annulation d'un geste (titre à modèle, légende, lieu, note,
  étiquette, mots-clés, décalage de date), annexes XMP (écriture dans Metadonnees/, lecture, priorité catalogue / annexe).
- **Variantes** (photo de référence et ses variantes, masquées par défaut), **catégories de mots-clés**, critère « sauvegarde »,
  photos **récemment vues**, **comparaison** de 2 à 4 photos, raccourcis clavier de la visionneuse (iPad : 0-5 notes, flèches, I).
- Tableau de bord exportable en PDF.

### Modifié

- Schéma de la base : version 4 (migrations 1 → 4 testées sur des bases des versions précédentes).
- Les sauvegardes emportent aussi retouches, albums, catégories et variantes (archives plus anciennes toujours lisibles).

## [0.4.0] — 2026-11-25

### Ajouté

- **Albums** : formats (A4, carrés, 20 × 30…, personnalisé), 12 gabarits identiques à ceux de la version de bureau (dont 4 doubles pages),
  pages, recadrage manuel (même calcul que le bureau), glisser-déposer entre cadres, titres et légendes, modèles graphiques,
  annuler / rétablir, remplissage automatique, contrôles avant impression (résolution effective, photos manquantes, doubles pages mal
  placées), **export PDF** (impression 300 ppp / écran 150 ppp, fond perdu 3 mm, pages ou planches), **projet `.album.json`
  échangeable avec la version de bureau** (photos retrouvées par empreinte SHA-256).
- **Documents PDF** : planches-contact, fiches détaillées, catalogues thématiques (regroupement par année, mois, mot-clé, lieu, appareil,
  note, sommaire), portfolios.

## [0.3.0] — 2026-11-25

### Ajouté

- **Retouche non destructive** : exposition, luminosité, contraste, hautes lumières, ombres, température, teinte, vibrance, saturation,
  netteté, bruit, courbe de tonalité (éditeur de points), noir et blanc, sépia, rotation, miroir, redressement, recadrage ; 9
  préréglages ; plusieurs versions par photo, version par défaut affichée partout ; annuler / rétablir (50 étapes) ; comparaison avec
  l'original. L'original n'est jamais modifié.
- **Exports** : JPEG, PNG, HEIC ; qualité ; taille ou **tirage aux dimensions physiques** (10 × 15 … 30 × 45 cm, définition réglable) ;
  retouches ; métadonnées (conserver, sans position GPS, aucune) ; filigrane ; profil sRGB / Display P3 ; modèle de nom ; jamais d'écrasement.

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

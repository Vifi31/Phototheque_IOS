# Photothèque et iOS : compatibilité

Ce document fait l'état des lieux de la compatibilité avec iOS. Il compare la
Photothèque de bureau (version 0.30.0, dépôt
[Vifi31/Phototheque](https://github.com/Vifi31/Phototheque)) avec la version
iOS de ce dépôt. Il a été établi le 8 novembre 2026.

## 1. La version de bureau ne peut pas fonctionner sur iPhone ou iPad

Les causes sont techniques, sans contournement acceptable.

| Brique de bureau | Situation sur iOS |
| --- | --- |
| **Node.js 24** (moteur de l'application) | iOS n'exécute pas Node.js. Apple interdit aux apps de télécharger et lancer un autre moteur de code. Le projet « nodejs-mobile » est figé en Node 18, qui n'a pas `node:sqlite`. |
| **`node:sqlite`** (base) | Absent sur iOS, mais SQLite est fourni par le système. → La base reste SQLite, utilisée directement par Swift. |
| **sharp / libvips** (images) | Binaires natifs compilés pour Windows, macOS et Linux, jamais pour iOS. → Remplacés par **ImageIO** (vignettes, métadonnées) et **CryptoKit** (SHA-256), fournis par iOS. |
| **exifr** (EXIF, IPTC, XMP) | → Remplacé par ImageIO, qui lit EXIF, TIFF, GPS et IPTC. |
| **Serveur web local + interface dans le navigateur** | Une app iOS ne peut pas laisser tourner un serveur en arrière-plan. → L'interface est réécrite en **SwiftUI**. |
| **Indexation sans copie de dossiers quelconques** | Le bac à sable d'iOS interdit de parcourir le disque. → **Import par copie** depuis l'app Photos (sélecteur système) ou depuis Fichiers. Les originaux ne sont ni modifiés ni supprimés. |
| **Installateur IExpress / PowerShell, signature Ed25519** | Une app iOS s'installe par Xcode, TestFlight, l'App Store, ou par chargement latéral avec un identifiant Apple. Elle est signée par Apple. Voir [INSTALLATION-IOS.md](INSTALLATION-IOS.md). |
| **« Ouvrir dans… » un logiciel externe** | → Feuille de partage d'iOS. |
| **Guide PDF généré par Edge** | Sans objet. |

## 2. L'interface web de bureau ouverte dans Safari sur iPhone

L'interface a été testée à la taille d'un iPhone (375 × 812 points) :

- la page s'affiche sans défilement horizontal ;
- la balise `viewport` est présente ;
- la grille et les filtres s'empilent en colonne.

Elle reste pourtant inutilisable sur iPhone :

- **inaccessible depuis l'iPhone** : le serveur n'écoute que sur 127.0.0.1, l'ordinateur lui-même, par sécurité ;
- **gestes souris sans équivalent tactile** :
  - glisser-déposer HTML5 entre les cadres d'album ;
  - zoom au double-clic et à la molette ;
  - raccourcis clavier de classement (0-9, I, K, Z) ;
- **chemins de dossiers tapés à la main** pour l'indexation et l'import ;
- **écran trop petit** : la barre latérale et la barre du haut prennent la moitié de l'écran.

C'est pourquoi une **application iOS autonome** a été écrite, à la demande de
l'utilisateur. Elle ne dépend pas d'un ordinateur.

## 3. Ce que fait la version iOS 0.5.0

Le cœur (`Core/`, Swift pur + SQLite) reprend les règles de la version de bureau (0.37.0) : import sans jamais toucher à l'original,
doublons exacts par SHA-256, recherche insensible aux accents, mots-clés hiérarchiques, sauvegarde de sécurité avant restauration.
Les tableaux classent les domaines de la version de bureau selon leur état dans la version iOS.

### Présents

| Domaine (bureau) | iOS 0.5.0 |
| --- | --- |
| Catalogue SQLite, migrations, intégrité | Schéma versionné (version 4), migrations testées depuis les versions 1 à 3, contrôle d'intégrité. |
| Import, doublons exacts, noms uniques | Depuis Photos (fichier d'origine) et Fichiers ; re-sélection reconnue. |
| Métadonnées EXIF / IPTC / GPS | Lues à l'import (ImageIO). |
| Notes, étiquettes, titre, légende, lieu | Oui, modification unitaire et **en masse avec aperçu et annulation**. |
| Mots-clés hiérarchiques, synonymes, catégories, doublons de vocabulaire | Oui. |
| Recherche et filtres | Texte, années / appareils / formats / mots-clés **à choix multiples**, note, étiquette, GPS, lieu, objectif, orientation, manques, catégorie, état de sauvegarde, description (IA), **ET / OU**. |
| Collections et recherches enregistrées | Oui (les recherches de la version 0.1 restent lisibles). |
| Photos semblables, variantes, référence | dHash, variantes masquées par défaut, jamais de suppression automatique. |
| Retouche non destructive | Réglages de lumière, couleur, détail, courbe, géométrie ; versions, annuler / rétablir. RAW : sur l'aperçu fourni par iOS. |
| Exports | JPEG / PNG / HEIC, taille ou tirage physique, filigrane, profil, métadonnées, noms. |
| Albums, doubles pages, recadrage, annuler | Oui ; **PDF** (impression, écran, fond perdu, planches) ; projet `.album.json` **échangeable avec le bureau**. |
| Planches-contact, fiches, catalogues, portfolios | PDF. |
| Rapports | Inventaire, fichiers manquants, intégrité, sauvegardes, photos à documenter (CSV, PDF). |
| Tableau de bord | Chiffres, graphiques, répartitions cliquables, manques, volumes ; CSV et PDF. |
| Sauvegardes | ZIP vérifiables, **chiffrées AES-256**, planifiées, rotation, copies vers Fichiers, alertes, **test de restauration**, **restauration sélective**. |
| Verrouillage | Face ID / code de l'appareil. |
| Annexes XMP | Écriture dans `Metadonnees/`, lecture, priorité catalogue / annexe. |
| Assistant IA local | Vision (sur l'appareil) : suggestions à valider, recherche par description, événements, lieux, photos proches. |
| Navigation | Tailles de vignettes, zoom, récemment vues, comparaison, raccourcis clavier (iPad). |
| À propos, mise à jour | Version, recherche de mise à jour sur GitHub, téléchargement de l'`.ipa` vérifié par SHA-256 (l'installation reste à faire par Sideloadly / AltStore / TestFlight). |

### Impossibles ou différents sur iOS

| Domaine (bureau) | Pourquoi / équivalent |
| --- | --- |
| Supports de stockage, indexation sans copie de dossiers | Le bac à sable d'iOS interdit de parcourir le disque. → Import par copie. |
| Cartes mémoire, clés USB, téléphones branchés (détection) | Pas de lecteurs sous iOS : l'app Fichiers et le sélecteur de Photos les remplacent. |
| Installateur, signature Ed25519, mise à jour automatique | Une app iOS est signée par Apple et s'installe par Xcode, TestFlight, l'App Store ou chargement latéral. |
| Sauvegarde programmée en arrière-plan | iOS n'offre pas de tâche planifiée fiable : rappel ou sauvegarde automatique à l'ouverture. |
| Ouvrir dans un logiciel externe | Feuille de partage d'iOS. |
| Moteurs d'IA externes sous licence | Remplacés par Vision (intégré à iOS). |
| Échange direct du catalogue | Les formats de sauvegarde diffèrent. Les **albums** s'échangent (projet `.album.json`), le **CSV** est lisible des deux côtés. |
| Courbes de tonalité en gamut large, profils ICC de sortie personnalisés | Profils sRGB et Display P3 seulement. |
| Bruit chromatique distinct, hautes lumières positives | Approximés par le moteur CoreImage (limite indiquée). |

## 4. Matériel et versions

- **Système** : iOS 17 ou plus récent ; même programme pour iPhone et iPad.
- **Formats** : ceux que lit iOS, c'est-à-dire JPEG, HEIC/HEIF, PNG, TIFF, GIF, et les RAW pris en charge par ImageIO, comme le DNG et la plupart des boîtiers récents.
- **Espace** : chaque photo importée est copiée. Le volume est indiqué dans les Réglages.

## 5. Ce qui a été vérifié, et comment

| Vérification | Moyen | Résultat |
| --- | --- | --- |
| Cœur Swift | `scripts/test-wsl.sh` sous Windows + WSL (Ubuntu 26.04, Swift 6.4.2). | 97 tests réussis. |
| Cœur Swift sur la plateforme Apple | CI GitHub (macOS : CryptoKit, SQLite du système). | Voir la dernière exécution de la CI. |
| Compilation de l'app iOS | CI GitHub : Xcode, compilation simulateur et iPhone. | Voir la dernière exécution de la CI. |
| Lancement réel | CI GitHub, simulateur iPhone : import automatique de 3 photos d'essai, puis contrôle dans la base (métadonnées, empreintes, vignettes) et contrôle que l'app tourne encore. | Voir la dernière exécution de la CI. |
| Sur un vrai iPhone | — | **Non essayé** : aucun appareil n'est relié au poste de développement. |

L'interface SwiftUI ne se compile pas sous Linux. Elle n'est vérifiée que par
la CI macOS.

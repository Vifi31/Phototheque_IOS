# Photothèque pour iOS

Application **iPhone / iPad autonome** (iOS 17+) de gestion d'un fonds photographique
personnel, déclinaison de la [Photothèque de bureau](https://github.com/Vifi31/Phototheque).
Tout reste sur l'appareil : aucun compte, aucun serveur.

- Import depuis l'app **Photos** ou **Fichiers** — copie, l'original n'est jamais modifié ;
  doublons exacts reconnus (SHA-256).
- Notes, étiquettes de couleur, titre, légende, lieu ; métadonnées EXIF / IPTC / GPS lues à l'import.
- **Mots-clés hiérarchiques** avec synonymes, fusion des doublons de vocabulaire.
- **Recherche** insensible aux accents + filtres (année, note, étiquette, mot-clé, appareil, GPS, manques).
- **Collections** et recherches enregistrées.
- **Photos semblables** (empreinte visuelle).
- **Filtres** à choix multiples, critères **ET / OU**, **tableau de bord** et **rapports** (CSV, PDF).
- **Retouche non destructive** (versions, courbe, préréglages) et **exports** (taille ou tirage, filigrane, profil, métadonnées).
- **Albums** à gabarits (doubles pages, recadrage, annuler), **export PDF**, projet échangeable avec la version de bureau ;
  planches-contact, fiches, catalogues thématiques, portfolios.
- **Sauvegardes** ZIP vérifiables, **chiffrées** (AES-256), planifiées, copiées hors de l'appareil, test de restauration,
  restauration sélective, verrouillage Face ID.
- **Assistant IA local** (Vision, sur l'appareil) : mots-clés suggérés à valider, recherche par description, événements.
- **Métadonnées** en masse (aperçu, annulation), annexes XMP, variantes, catégories de mots-clés.
- **À propos** : version et recherche de mise à jour sur GitHub.

## Documentation

- [Compatibilité iOS](docs/COMPATIBILITE.md) — pourquoi la version de bureau ne tourne pas sur iOS,
  ce que couvre la version 0.5.0, ce qui a été vérifié.
- [Guide d'installation pour débutants (Word)](docs/Guide-installation-iOS.docx) — pas à pas, sans connaissance technique.
- [Installation](docs/INSTALLATION-IOS.md) — depuis Windows sans Mac, avec Xcode, ou TestFlight / App Store.
- [Journal des versions](CHANGELOG.md).

## Organisation

```
Core/                     paquet Swift « PhotothequeCore » (sans interface, testable sous Linux)
  Sources/PhotothequeCore SQLite, schéma, catalogue, mots-clés, recherche, collections, doublons, variantes,
                          retouches, exports, albums, documents, tableau de bord, rapports, métadonnées, XMP, IA,
                          SHA-256 / CRC-32 / dHash, ZIP, sauvegardes chiffrées, mise à jour
  Sources/CSQLite         accès à libsqlite3 sous Linux uniquement
  Tests/                  tests XCTest
App/                      application SwiftUI (iOS) : vues, import, ImageIO, cache des vignettes
project.yml               projet Xcode (XcodeGen)
ci/photos/                photos d'essai importées par la CI dans le simulateur
scripts/test-wsl.sh       tests du cœur sous Windows + WSL
.github/workflows/ci.yml  tests Linux + macOS, compilation iOS, lancement simulateur, .ipa
```

## Développer

```bash
# Cœur : Linux, WSL ou macOS
scripts/test-wsl.sh            # ou : swift test --package-path Core

# Application : macOS + Xcode
brew install xcodegen && xcodegen generate && open Phototheque.xcodeproj
```

Chaque envoi sur `main` lance la CI : tests du cœur sous Linux et macOS, compilation de l'app,
lancement dans un simulateur iPhone avec import de photos d'essai, `.ipa` non signée en artefact.
Un tag `v*` publie l'`.ipa` dans les Releases.

## Licence

Voir [LICENSE](LICENSE).

# Credits

## Photos (Wikimedia Commons)

| File in app | Subject | Author | Licence |
|---|---|---|---|
| `forum` | Pompeii Forum & Mt. Vesuvius | Gary Todd | CC0 |
| `thermo` | Thermopolium of Vetutius Placidus | Gary Todd | Public domain |
| `shrine` | Thermopolium shrine (lararium) of Lucius Vetutius Placidus | Jebulon | CC0 |
| `forum1841` | *The Forum, Pompeii, with Vesuvius in the Distance* (1841), painting | Christen Schjellerup Købke | Public domain |
| `caveCanem` | Cave canem mosaic, House of the Tragic Poet (cropped) | Argo Navis | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) |

### Naples

| File in app | Subject | Author | Licence |
|---|---|---|---|
| `gesuFacade` | Façade of Gesù Nuovo | Berthold Werner | CC BY-SA 3.0 |
| `gesuFacade2` | Chiesa del Gesù Nuovo | Rutger van der Maar | CC BY 2.0 |
| `gesuDetail` | Gesù Nuovo, rusticated façade | Punteador | CC BY-SA 4.0 |
| `plebiscito` | Piazza del Plebiscito, San Francesco di Paola | Vyacheslav Argenberg | CC BY 4.0 |
| `plebiscitoVesuvius` | Vesuvius from Piazza del Plebiscito | Roma1314 | CC BY-SA 3.0 |
| `plebiscitoCarPark` | Piazza del Plebiscito as a car park | Unknown author | Public domain |
| `sansevero` | Cappella Sansevero, the Veiled Christ | David Sivyer | CC BY-SA 2.0 |
| `veiledChristFace` | Veiled Christ, face | David Sivyer | CC BY-SA 2.0 |
| `castelOvo` | Castel dell’Ovo 01 | Bernard Gagnon | CC BY 4.0 |
| `castelOvo2` | Castel dell’Ovo | Livioandronico2013 | CC BY-SA 4.0 |

All from Wikimedia Commons. CC BY-SA images are resized and cropped here and shared under the same licence, with attribution.

Test fixtures in `CheStoriaTests/Fixtures` (used only to test recognition): Pompeii Forum (Gary Todd, CC0), Cave canem mosaic (Yair Haklai, CC BY-SA 4.0), Stepping stones at Via del Tempio d’Iside (Gary Todd, public domain).

The Cave canem photo is shared under CC BY-SA 4.0: the cropped version in this repository is shared under the same licence, with attribution to Argo Navis.

## AI model

- **SigLIP** (google/siglip-base-patch16-224) by Google, Apache License 2.0. The image encoder is converted to Core ML and compressed; see `CheStoria/Resources/ML/NOTICE.md` and the licence file next to it.

Test fixtures for "not a place": cup of coffee in Café Butter, Berlin (Edward, CC0); Computer desk at Narita Airport (D Coetzee, CC0).

## Fonts

- **Bricolage Grotesque** by Mathieu Triay and the Bricolage Grotesque Project Authors, SIL Open Font License 1.1 (`CheStoria/Resources/Fonts/OFL-Bricolage.txt`). The ExtraBold and Bold files are static instances made from the variable font.
- **Kalam** by the Indian Type Foundry, SIL Open Font License 1.1 (`CheStoria/Resources/Fonts/OFL-Kalam.txt`).
- SF Pro is the system font and is not included.

## Research

The design rules come from the team's research deck (Storia Pitch v4), including Bitgood (label length), Tassiello & Tillotson 2020 (2 vs 8+ facts), Loewenstein 1994 (information gap), Gruber et al. 2014 (curiosity and memory), Henkel 2014 (photographing details), Beattie & Schneider 2018 (self-guided visitors) and Brooklyn Museum 2017 (phone use vs app downloads).

Profil de configuration: Vérification des signatures de paquetages
==================================================================

Voici le détail du contenu du dossier params/update_keys qui contient le
matériel cryptographique nécessaire à la vérification des signatures des
paquets à mettre à jour.


Cryptographie gouvernementale (CCSD)
------------------------------------

params/update_keys
├── ctrl.bin      --> Certificat racine pour valider les certificats des contrôleurs
├── ctrl.bin.txt  --> Mot de passe pour déchiffre le certificat racine contrôleur
├── dev.bin       --> Certificat racine pour valider les certificats des développeurs
└── dev.bin.txt   --> Mot de passe pour déchiffre le certificat racine développeur


Cryptographie civile (OpenSSL)
------------------------------

params/update_keys
├── certs_ctrl        --> Dossier contenant l'ensemble des certificats
│   ├── ctrl.pem          nécessaires à la vérification des certificats
│   └── root.pem          contrôleurs.
│
├── certs_dev         --> Dossier contenant l'ensemble des certificats
│   ├── dev.pem           nécessaires à la vérification des certificats
│   └── root.pem          développeurs.
│
├── crl_ctrl          --> Dossier contenant les CRLs des autorités de
│   ├── crl.pem           certification pour les contrôleurs.
│   └── crl_root.pem
│
├── crl_dev           --> Dossier contenant les CRLs des autorités de
│   ├── crl.pem           certification pour les développeurs.
│   └── crl_root.pem
│
└── trusted_ca.conf   --> Fichier définissant les uniques certificats valides
                          pour vérifier les certificats développeurs et
                          contrôleurs. Exemple:
                          TRUSTED_CA_DEV=dev.pem
                          TRUSTED_CA_CTRL=ctrl.pem

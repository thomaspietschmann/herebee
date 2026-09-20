/**
 * Tiny UI translation layer. All user-facing strings live here, keyed; the rest
 * of the app calls t(key, params?). Language is picked once from the device
 * locale (navigator.language) and is stable for the session — German for de*,
 * else English/Spanish/Italian/French/Portuguese, falling back to English.
 *
 * Strings may contain inline HTML (<strong>, <em>, <code>) because they are
 * inserted via innerHTML in the sheets; keep the markup identical across langs.
 */

export type Lang = "de" | "en" | "es" | "it" | "fr" | "pt";
const SUPPORTED: readonly Lang[] = ["de", "en", "es", "it", "fr", "pt"];

function detectLang(): Lang {
  try {
    const list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language];
    for (const l of list) {
      const code = (l || "").toLowerCase().slice(0, 2) as Lang;
      if (SUPPORTED.includes(code)) return code;
    }
  } catch {
    /* ignore */
  }
  return "en"; // sensible default for non-DACH devices
}

export const lang: Lang = detectLang();

// German is the source of truth and defines the key set.
const de = {
  title: "HereBee — flüchtig zusammenfinden",
  hint: "Nur aktive Teilnehmer sehen dich. Standorte werden Ende-zu-Ende verschlüsselt und nicht gespeichert.",
  shareLink: "Link teilen",
  shareLocation: "Standort teilen",
  stopSharing: "Teilen stoppen",
  infoAria: "Wie anonym ist das?",
  close: "Schließen",
  connOn: "Verbunden",
  connOff: "Getrennt",
  connConnecting: "Verbindung…",
  here: "{n} hier",
  hereActiveOffline: "{active} aktiv · {offline} offline",
  youSuffix: "(du)",
  linkCopied: "Link kopiert",
  shareTitle: "Raum teilen",
  shareBody:
    "Wer diesen Link öffnet, tritt dem Raum bei und sieht die Live-Standorte. Der Link <strong>ist</strong> der Schlüssel — teile ihn bewusst.",
  copy: "Kopieren",
  welcomeTitle: "Willkommen bei HereBee",
  welcomeIntro: "Du bist in einem privaten Raum. Alle mit diesem Link finden sich hier live auf der Karte.",
  welcomeFact1:
    "<strong>Anwesenheit:</strong> Sobald du den Raum betrittst, sehen die anderen, dass jemand da ist — nur eine Zahl, ohne Name oder Standort. Vorher wird nichts übertragen.",
  welcomeFact2:
    "<strong>Nur zuschauen ist okay:</strong> Du musst deinen Standort nicht teilen und bleibst dann eine anonyme Zahl. Tippe auf <em>„Standort teilen“</em>, damit <strong>alle im Raum</strong> deinen Live-Standort sehen — Ende-zu-Ende-verschlüsselt, nichts wird gespeichert.",
  welcomeFact3:
    "<strong>Jederzeit stoppen:</strong> Der Button wird zu <em>„Teilen stoppen“</em> — ein Tipp, und du teilst nichts mehr.",
  welcomeCta: "Raum betreten",
  watcher: "Schaut zu",
  participantsTitle: "Wer ist hier?",
  fitAll: "Alle auf einen Blick",
  watchingLine: "{n} schauen zu (anonym)",
  noSharers: "Noch niemand teilt seinen Standort.",
  renameTitle: "Namen vergeben",
  renameBody: "Nur für dich sichtbar, lokal auf diesem Gerät gespeichert.",
  renamePlaceholder: "z. B. Anna",
  save: "Speichern",
  renameReset: "Auf Zufallsnamen zurücksetzen",
  invalidTitle: "Dieser Link führt nirgendwo hin",
  invalidBody:
    "Der Raum-Schlüssel im Link fehlt oder ist unvollständig. Raum-Links werden automatisch erzeugt — man kann sie nicht von Hand eintippen.",
  invalidCta: "Neuen Raum öffnen",
  infoTitle: "Wie privat ist das?",
  infoIntro:
    "HereBee teilt Standorte <strong>flüchtig und Ende-zu-Ende-verschlüsselt</strong> zwischen aktiven Teilnehmern. Es ist bewusst datensparsam — aber nenne es nicht „vollständig anonym“.",
  infoFact1:
    "Der Server sieht <strong>weder Koordinaten noch Namen noch den Schlüssel</strong> — nur verschlüsselte Datenpakete.",
  infoFact2: "Der Schlüssel steckt im Link hinter <code>#</code> und wird nie an den Server gesendet.",
  infoFact3:
    "Es gibt <strong>keine Datenbank</strong>; die App speichert nichts und führt keine eigenen Zugriffs-Logs. Räume leben nur, solange jemand da ist.",
  infoFact4:
    "Der HereBee-Server (Relay und selbst gehostete Karten) sieht deine <strong>IP</strong> für die Dauer der Verbindung und kann an den geladenen Kartenkacheln grob deine Region ablesen. Die App speichert das nicht, aber vorgelagerte Infrastruktur (Proxy/Hoster) kann Logs führen. Keine fremden Karten- oder CDN-Dienste; die eigene IP lässt sich im Browser generell nicht verbergen.",
  infoFact5:
    "Wer den vollständigen Link hat, sieht den Raum — und alle im Raum teilen denselben Schlüssel, könnten also den Marker eines anderen fälschen. Teile den Link nur mit Vertrauten.",
  mapCredits: "Karte: {pm} © {osm}-Mitwirkende",
  legalLink: "Impressum & Datenschutz",
  noGeo: "Dieses Gerät kann keinen Standort teilen",
  geoDenied: "Standortfreigabe wurde abgelehnt",
  geoUnavailable: "Standort nicht verfügbar",
  fatalInvalidRoom: "Ungültiger Raum-Link",
  fatalRejected: "Verbindung abgelehnt",
  justNow: "gerade eben",
  secsAgo: "vor {n} s",
  minsAgo: "vor {n} min",
  noSignal: "kein Signal ({t})",
  noSignalLong: "lange kein Signal ({t})",
  offlineStatus: "offline",
  menuRenameAria: "Namen ändern",
  menuFollow: "Folgen",
  menuUnfollow: "Folgen beenden",
  infoLastSeen: "Zuletzt gesehen: {t}",
  infoDistance: "{d} entfernt",
  statusOnline: "Online",
  statusNoSignal: "Kein Signal",
} as const;

export type Key = keyof typeof de;

const en: Record<Key, string> = {
  title: "HereBee — meet up, fleetingly",
  hint: "Only active participants can see you. Locations are end-to-end encrypted and never stored.",
  shareLink: "Share link",
  shareLocation: "Share location",
  stopSharing: "Stop sharing",
  infoAria: "How anonymous is this?",
  close: "Close",
  connOn: "Connected",
  connOff: "Disconnected",
  connConnecting: "Connecting…",
  here: "{n} here",
  hereActiveOffline: "{active} active · {offline} offline",
  youSuffix: "(you)",
  linkCopied: "Link copied",
  shareTitle: "Share room",
  shareBody:
    "Anyone who opens this link joins the room and sees the live locations. The link <strong>is</strong> the key — share it deliberately.",
  copy: "Copy",
  welcomeTitle: "Welcome to HereBee",
  welcomeIntro: "You're in a private room. Everyone with this link meets here live on the map.",
  welcomeFact1:
    "<strong>Presence:</strong> The moment you enter the room, the others see that someone is here — just a number, no name or location. Nothing is transmitted before that.",
  welcomeFact2:
    "<strong>Just watching is fine:</strong> You don't have to share your location — you stay an anonymous number. Tap <em>“Share location”</em> so <strong>everyone in the room</strong> sees your live location — end-to-end encrypted, nothing is stored.",
  welcomeFact3:
    "<strong>Stop anytime:</strong> The button turns into <em>“Stop sharing”</em> — one tap and you share nothing again.",
  welcomeCta: "Enter room",
  watcher: "Watching",
  participantsTitle: "Who's here?",
  fitAll: "Fit everyone on screen",
  watchingLine: "{n} watching (anonymous)",
  noSharers: "Nobody is sharing a location yet.",
  renameTitle: "Set a name",
  renameBody: "Visible only to you, stored locally on this device.",
  renamePlaceholder: "e.g. Anna",
  save: "Save",
  renameReset: "Reset to random name",
  invalidTitle: "This link leads nowhere",
  invalidBody:
    "The room key in the link is missing or incomplete. Room links are generated automatically — you can't type them by hand.",
  invalidCta: "Open a new room",
  infoTitle: "How private is this?",
  infoIntro:
    "HereBee shares locations <strong>ephemerally and end-to-end encrypted</strong> between active participants. It's deliberately data-minimal — but don't call it “fully anonymous”.",
  infoFact1: "The server sees <strong>neither coordinates nor names nor the key</strong> — only encrypted packets.",
  infoFact2: "The key sits in the link after <code>#</code> and is never sent to the server.",
  infoFact3:
    "There is <strong>no database</strong>; the app stores nothing and keeps no access logs of its own. Rooms exist only while someone is present.",
  infoFact4:
    "The HereBee server (relay and self-hosted maps) sees your <strong>IP</strong> for the duration of the connection and can roughly tell which area you're viewing from the map tiles you load. The app doesn't log this, but upstream infrastructure (proxy/host) may. No third-party map or CDN services; a browser generally can't hide your IP.",
  infoFact5:
    "Anyone with the full link can see the room — and everyone in it shares the same key, so a participant could spoof another's marker. Share the link only with people you trust.",
  mapCredits: "Map: {pm} © {osm} contributors",
  legalLink: "Legal notice & privacy",
  noGeo: "This device can't share a location",
  geoDenied: "Location permission denied",
  geoUnavailable: "Location unavailable",
  fatalInvalidRoom: "Invalid room link",
  fatalRejected: "Connection rejected",
  justNow: "just now",
  secsAgo: "{n}s ago",
  minsAgo: "{n}m ago",
  noSignal: "no signal ({t})",
  noSignalLong: "no signal for a while ({t})",
  offlineStatus: "offline",
  menuRenameAria: "Change name",
  menuFollow: "Follow",
  menuUnfollow: "Stop following",
  infoLastSeen: "Last seen: {t}",
  infoDistance: "{d} away",
  statusOnline: "Online",
  statusNoSignal: "No signal",
};

const es: Record<Key, string> = {
  title: "HereBee — encontrarse al instante",
  hint: "Solo los participantes activos te ven. Las ubicaciones se cifran de extremo a extremo y no se guardan.",
  shareLink: "Compartir enlace",
  shareLocation: "Compartir ubicación",
  stopSharing: "Dejar de compartir",
  infoAria: "¿Cómo de anónimo es esto?",
  close: "Cerrar",
  connOn: "Conectado",
  connOff: "Desconectado",
  connConnecting: "Conectando…",
  here: "{n} aquí",
  hereActiveOffline: "{active} activo · {offline} sin conexión",
  youSuffix: "(tú)",
  linkCopied: "Enlace copiado",
  shareTitle: "Compartir sala",
  shareBody:
    "Quien abra este enlace entra en la sala y ve las ubicaciones en vivo. El enlace <strong>es</strong> la clave: compártelo con cuidado.",
  copy: "Copiar",
  welcomeTitle: "Bienvenido a HereBee",
  welcomeIntro: "Estás en una sala privada. Todos los que tengan este enlace se encuentran aquí en vivo en el mapa.",
  welcomeFact1:
    "<strong>Presencia:</strong> En cuanto entras en la sala, los demás ven que hay alguien — solo un número, sin nombre ni ubicación. Antes no se transmite nada.",
  welcomeFact2:
    "<strong>Solo mirar está bien:</strong> No tienes que compartir tu ubicación y sigues siendo un número anónimo. Toca <em>«Compartir ubicación»</em> para que <strong>todos en la sala</strong> vean tu ubicación en vivo: cifrada de extremo a extremo, no se guarda nada.",
  welcomeFact3:
    "<strong>Detente cuando quieras:</strong> El botón cambia a <em>«Dejar de compartir»</em>: un toque y dejas de compartir.",
  welcomeCta: "Entrar en la sala",
  watcher: "Mirando",
  participantsTitle: "¿Quién está aquí?",
  fitAll: "Ver a todos en pantalla",
  watchingLine: "{n} mirando (anónimo)",
  noSharers: "Todavía nadie comparte su ubicación.",
  renameTitle: "Poner un nombre",
  renameBody: "Visible solo para ti, guardado localmente en este dispositivo.",
  renamePlaceholder: "p. ej. Anna",
  save: "Guardar",
  renameReset: "Restablecer al nombre aleatorio",
  invalidTitle: "Este enlace no lleva a ninguna parte",
  invalidBody:
    "Falta la clave de la sala en el enlace o está incompleta. Los enlaces de sala se generan automáticamente: no se pueden escribir a mano.",
  invalidCta: "Abrir una sala nueva",
  infoTitle: "¿Cómo de privado es esto?",
  infoIntro:
    "HereBee comparte ubicaciones <strong>de forma efímera y cifrada de extremo a extremo</strong> entre participantes activos. Recopila los mínimos datos posibles, pero no lo llames «totalmente anónimo».",
  infoFact1: "El servidor no ve <strong>ni coordenadas, ni nombres, ni la clave</strong>: solo paquetes cifrados.",
  infoFact2: "La clave está en el enlace después de <code>#</code> y nunca se envía al servidor.",
  infoFact3:
    "No hay <strong>base de datos</strong>; la app no guarda nada ni mantiene registros de acceso propios. Las salas existen solo mientras hay alguien.",
  infoFact4:
    "El servidor de HereBee (relay y mapas alojados por nosotros mismos) ve tu <strong>IP</strong> mientras dura la conexión y, por las teselas del mapa que cargas, puede deducir aproximadamente qué zona miras. La app no lo registra, pero la infraestructura previa (proxy/hosting) sí puede. No hay servicios de mapas o CDN de terceros; el navegador no puede ocultar tu IP en general.",
  infoFact5:
    "Cualquiera con el enlace completo ve la sala, y todos en ella comparten la misma clave, así que un participante podría falsificar el marcador de otro. Comparte el enlace solo con personas de confianza.",
  mapCredits: "Mapa: {pm} © colaboradores de {osm}",
  legalLink: "Aviso legal y privacidad",
  noGeo: "Este dispositivo no puede compartir la ubicación",
  geoDenied: "Se denegó el permiso de ubicación",
  geoUnavailable: "Ubicación no disponible",
  fatalInvalidRoom: "Enlace de sala no válido",
  fatalRejected: "Conexión rechazada",
  justNow: "ahora mismo",
  secsAgo: "hace {n} s",
  minsAgo: "hace {n} min",
  noSignal: "sin señal ({t})",
  noSignalLong: "sin señal desde hace rato ({t})",
  offlineStatus: "sin conexión",
  menuRenameAria: "Cambiar nombre",
  menuFollow: "Seguir",
  menuUnfollow: "Dejar de seguir",
  infoLastSeen: "Visto por última vez: {t}",
  infoDistance: "A {d}",
  statusOnline: "En línea",
  statusNoSignal: "Sin señal",
};

const it: Record<Key, string> = {
  title: "HereBee — ritrovarsi al volo",
  hint: "Solo i partecipanti attivi ti vedono. Le posizioni sono cifrate end-to-end e non vengono memorizzate.",
  shareLink: "Condividi link",
  shareLocation: "Condividi posizione",
  stopSharing: "Interrompi condivisione",
  infoAria: "Quanto è anonimo?",
  close: "Chiudi",
  connOn: "Connesso",
  connOff: "Disconnesso",
  connConnecting: "Connessione…",
  here: "{n} qui",
  hereActiveOffline: "{active} attivo · {offline} offline",
  youSuffix: "(tu)",
  linkCopied: "Link copiato",
  shareTitle: "Condividi stanza",
  shareBody:
    "Chi apre questo link entra nella stanza e vede le posizioni in tempo reale. Il link <strong>è</strong> la chiave: condividilo con attenzione.",
  copy: "Copia",
  welcomeTitle: "Benvenuto su HereBee",
  welcomeIntro: "Sei in una stanza privata. Tutti quelli che hanno questo link si ritrovano qui, live sulla mappa.",
  welcomeFact1:
    "<strong>Presenza:</strong> Appena entri nella stanza, gli altri vedono che c'è qualcuno — solo un numero, senza nome né posizione. Prima non viene trasmesso nulla.",
  welcomeFact2:
    "<strong>Solo guardare va bene:</strong> Non devi condividere la tua posizione e resti un numero anonimo. Tocca <em>«Condividi posizione»</em> perché <strong>tutti nella stanza</strong> vedano la tua posizione in tempo reale: cifrata end-to-end, non viene memorizzato nulla.",
  welcomeFact3:
    "<strong>Fermati quando vuoi:</strong> Il pulsante diventa <em>«Interrompi condivisione»</em>: un tocco e non condividi più nulla.",
  welcomeCta: "Entra nella stanza",
  watcher: "Sta guardando",
  participantsTitle: "Chi c'è?",
  fitAll: "Mostra tutti sullo schermo",
  watchingLine: "{n} stanno guardando (anonimo)",
  noSharers: "Ancora nessuno condivide la posizione.",
  renameTitle: "Assegna un nome",
  renameBody: "Visibile solo a te, salvato localmente su questo dispositivo.",
  renamePlaceholder: "es. Anna",
  save: "Salva",
  renameReset: "Ripristina il nome casuale",
  invalidTitle: "Questo link non porta da nessuna parte",
  invalidBody:
    "La chiave della stanza nel link manca o è incompleta. I link delle stanze vengono generati automaticamente: non si possono digitare a mano.",
  invalidCta: "Apri una nuova stanza",
  infoTitle: "Quanto è privato?",
  infoIntro:
    "HereBee condivide le posizioni <strong>in modo effimero e cifrato end-to-end</strong> tra i partecipanti attivi. Raccoglie il minimo dei dati, ma non chiamarlo «completamente anonimo».",
  infoFact1: "Il server non vede <strong>né coordinate, né nomi, né la chiave</strong>: solo pacchetti cifrati.",
  infoFact2: "La chiave si trova nel link dopo <code>#</code> e non viene mai inviata al server.",
  infoFact3:
    "Non c'è <strong>alcun database</strong>; l'app non memorizza nulla e non tiene log di accesso propri. Le stanze esistono solo finché c'è qualcuno.",
  infoFact4:
    "Il server di HereBee (relay e mappe self-hosted) vede il tuo <strong>IP</strong> per la durata della connessione e, dalle tessere della mappa che carichi, può capire grossomodo quale zona stai guardando. L'app non lo registra, ma l'infrastruttura a monte (proxy/host) può farlo. Nessun servizio di mappe o CDN di terze parti; il browser in generale non può nascondere il tuo IP.",
  infoFact5:
    "Chiunque abbia il link completo vede la stanza, e tutti al suo interno condividono la stessa chiave, quindi un partecipante potrebbe falsificare il segnaposto di un altro. Condividi il link solo con persone fidate.",
  mapCredits: "Mappa: {pm} © contributori di {osm}",
  legalLink: "Note legali e privacy",
  noGeo: "Questo dispositivo non può condividere la posizione",
  geoDenied: "Autorizzazione alla posizione negata",
  geoUnavailable: "Posizione non disponibile",
  fatalInvalidRoom: "Link della stanza non valido",
  fatalRejected: "Connessione rifiutata",
  justNow: "proprio ora",
  secsAgo: "{n} s fa",
  minsAgo: "{n} min fa",
  noSignal: "nessun segnale ({t})",
  noSignalLong: "nessun segnale da un po' ({t})",
  offlineStatus: "offline",
  menuRenameAria: "Cambia nome",
  menuFollow: "Segui",
  menuUnfollow: "Smetti di seguire",
  infoLastSeen: "Visto l'ultima volta: {t}",
  infoDistance: "A {d} di distanza",
  statusOnline: "Online",
  statusNoSignal: "Nessun segnale",
};

const fr: Record<Key, string> = {
  title: "HereBee — se retrouver en un instant",
  hint: "Seuls les participants actifs te voient. Les positions sont chiffrées de bout en bout et ne sont pas conservées.",
  shareLink: "Partager le lien",
  shareLocation: "Partager ma position",
  stopSharing: "Arrêter le partage",
  infoAria: "À quel point est-ce anonyme ?",
  close: "Fermer",
  connOn: "Connecté",
  connOff: "Déconnecté",
  connConnecting: "Connexion…",
  here: "{n} ici",
  hereActiveOffline: "{active} actif · {offline} hors ligne",
  youSuffix: "(toi)",
  linkCopied: "Lien copié",
  shareTitle: "Partager le salon",
  shareBody:
    "Quiconque ouvre ce lien rejoint le salon et voit les positions en direct. Le lien <strong>est</strong> la clé — partage-le en connaissance de cause.",
  copy: "Copier",
  welcomeTitle: "Bienvenue sur HereBee",
  welcomeIntro:
    "Tu es dans un salon privé. Toute personne disposant de ce lien se retrouve ici, en direct sur la carte.",
  welcomeFact1:
    "<strong>Présence :</strong> Dès que tu entres dans le salon, les autres voient qu'il y a quelqu'un — juste un nombre, sans nom ni position. Rien n'est transmis avant.",
  welcomeFact2:
    "<strong>Juste regarder, c'est permis :</strong> Tu n'as pas à partager ta position et tu restes un nombre anonyme. Touche <em>« Partager ma position »</em> pour que <strong>tout le monde dans le salon</strong> voie ta position en direct — chiffrée de bout en bout, rien n'est conservé.",
  welcomeFact3:
    "<strong>Arrête quand tu veux :</strong> Le bouton devient <em>« Arrêter le partage »</em> — une touche et tu ne partages plus rien.",
  welcomeCta: "Entrer dans le salon",
  watcher: "Regarde",
  participantsTitle: "Qui est là ?",
  fitAll: "Tout le monde à l'écran",
  watchingLine: "{n} regardent (anonyme)",
  noSharers: "Personne ne partage encore sa position.",
  renameTitle: "Choisir un nom",
  renameBody: "Visible seulement par toi, enregistré localement sur cet appareil.",
  renamePlaceholder: "p. ex. Anna",
  save: "Enregistrer",
  renameReset: "Rétablir le nom aléatoire",
  invalidTitle: "Ce lien ne mène nulle part",
  invalidBody:
    "La clé du salon dans le lien est absente ou incomplète. Les liens de salon sont générés automatiquement — impossible de les saisir à la main.",
  invalidCta: "Ouvrir un nouveau salon",
  infoTitle: "À quel point est-ce privé ?",
  infoIntro:
    "HereBee partage les positions <strong>de façon éphémère et chiffrée de bout en bout</strong> entre participants actifs. C'est volontairement minimal en données — mais ne parle pas d'« anonymat total ».",
  infoFact1:
    "Le serveur ne voit <strong>ni les coordonnées, ni les noms, ni la clé</strong> — uniquement des paquets chiffrés.",
  infoFact2: "La clé se trouve dans le lien après <code>#</code> et n'est jamais envoyée au serveur.",
  infoFact3:
    "Il n'y a <strong>aucune base de données</strong> ; l'application ne stocke rien et ne tient aucun journal d'accès propre. Les salons n'existent que tant que quelqu'un est présent.",
  infoFact4:
    "Le serveur HereBee (relais et cartes auto-hébergées) voit ton <strong>IP</strong> pendant la durée de la connexion et peut, d'après les tuiles de carte que tu charges, deviner approximativement la zone que tu regardes. L'application ne l'enregistre pas, mais l'infrastructure en amont (proxy/hébergeur) le peut. Aucun service de cartes ou CDN tiers ; un navigateur ne peut généralement pas masquer ton IP.",
  infoFact5:
    "Quiconque possède le lien complet voit le salon — et tout le monde y partage la même clé, donc un participant pourrait falsifier le marqueur d'un autre. Ne partage le lien qu'avec des personnes de confiance.",
  mapCredits: "Carte : {pm} © contributeurs d'{osm}",
  legalLink: "Mentions légales & confidentialité",
  noGeo: "Cet appareil ne peut pas partager de position",
  geoDenied: "Autorisation de localisation refusée",
  geoUnavailable: "Position indisponible",
  fatalInvalidRoom: "Lien de salon invalide",
  fatalRejected: "Connexion refusée",
  justNow: "à l'instant",
  secsAgo: "il y a {n} s",
  minsAgo: "il y a {n} min",
  noSignal: "aucun signal ({t})",
  noSignalLong: "aucun signal depuis un moment ({t})",
  offlineStatus: "hors ligne",
  menuRenameAria: "Changer de nom",
  menuFollow: "Suivre",
  menuUnfollow: "Arrêter de suivre",
  infoLastSeen: "Vu pour la dernière fois : {t}",
  infoDistance: "À {d}",
  statusOnline: "En ligne",
  statusNoSignal: "Aucun signal",
};

const pt: Record<Key, string> = {
  title: "HereBee — encontrar-se num instante",
  hint: "Só os participantes ativos te veem. As localizações são cifradas de ponta a ponta e não são guardadas.",
  shareLink: "Partilhar link",
  shareLocation: "Partilhar localização",
  stopSharing: "Parar de partilhar",
  infoAria: "Quão anónimo é isto?",
  close: "Fechar",
  connOn: "Ligado",
  connOff: "Desligado",
  connConnecting: "A ligar…",
  here: "{n} aqui",
  hereActiveOffline: "{active} ativo · {offline} offline",
  youSuffix: "(tu)",
  linkCopied: "Link copiado",
  shareTitle: "Partilhar sala",
  shareBody:
    "Quem abrir este link entra na sala e vê as localizações em tempo real. O link <strong>é</strong> a chave — partilha-o com cuidado.",
  copy: "Copiar",
  welcomeTitle: "Bem-vindo ao HereBee",
  welcomeIntro: "Estás numa sala privada. Todos os que tiverem este link encontram-se aqui, ao vivo no mapa.",
  welcomeFact1:
    "<strong>Presença:</strong> Assim que entras na sala, os outros veem que está alguém — apenas um número, sem nome nem localização. Antes disso nada é transmitido.",
  welcomeFact2:
    "<strong>Só observar está bem:</strong> Não tens de partilhar a tua localização e continuas a ser um número anónimo. Toca em <em>«Partilhar localização»</em> para que <strong>todos na sala</strong> vejam a tua localização em tempo real — cifrada de ponta a ponta, nada é guardado.",
  welcomeFact3:
    "<strong>Para quando quiseres:</strong> O botão muda para <em>«Parar de partilhar»</em> — um toque e deixas de partilhar.",
  welcomeCta: "Entrar na sala",
  watcher: "A observar",
  participantsTitle: "Quem está aqui?",
  fitAll: "Mostrar todos no ecrã",
  watchingLine: "{n} a observar (anónimo)",
  noSharers: "Ainda ninguém partilha a localização.",
  renameTitle: "Definir um nome",
  renameBody: "Visível apenas para ti, guardado localmente neste dispositivo.",
  renamePlaceholder: "ex.: Anna",
  save: "Guardar",
  renameReset: "Repor o nome aleatório",
  invalidTitle: "Este link não leva a lado nenhum",
  invalidBody:
    "A chave da sala no link está em falta ou incompleta. Os links de sala são gerados automaticamente — não é possível escrevê-los à mão.",
  invalidCta: "Abrir uma nova sala",
  infoTitle: "Quão privado é isto?",
  infoIntro:
    "O HereBee partilha localizações <strong>de forma efémera e cifrada de ponta a ponta</strong> entre participantes ativos. Recolhe o mínimo de dados — mas não lhe chames «totalmente anónimo».",
  infoFact1: "O servidor não vê <strong>nem coordenadas, nem nomes, nem a chave</strong> — apenas pacotes cifrados.",
  infoFact2: "A chave está no link depois de <code>#</code> e nunca é enviada ao servidor.",
  infoFact3:
    "Não há <strong>base de dados</strong>; a app não guarda nada nem mantém registos de acesso próprios. As salas existem apenas enquanto alguém estiver presente.",
  infoFact4:
    "O servidor do HereBee (relay e mapas alojados por nós) vê o teu <strong>IP</strong> durante a ligação e, pelos tiles do mapa que carregas, consegue perceber aproximadamente que zona estás a ver. A app não regista isto, mas a infraestrutura a montante (proxy/alojamento) pode. Não há serviços de mapas ou CDN de terceiros; o navegador em geral não consegue ocultar o teu IP.",
  infoFact5:
    "Qualquer pessoa com o link completo vê a sala — e todos nela partilham a mesma chave, por isso um participante poderia falsificar o marcador de outro. Partilha o link apenas com pessoas de confiança.",
  mapCredits: "Mapa: {pm} © colaboradores do {osm}",
  legalLink: "Informação legal e privacidade",
  noGeo: "Este dispositivo não consegue partilhar a localização",
  geoDenied: "Permissão de localização recusada",
  geoUnavailable: "Localização indisponível",
  fatalInvalidRoom: "Link de sala inválido",
  fatalRejected: "Ligação recusada",
  justNow: "agora mesmo",
  secsAgo: "há {n} s",
  minsAgo: "há {n} min",
  noSignal: "sem sinal ({t})",
  noSignalLong: "sem sinal há um tempo ({t})",
  offlineStatus: "offline",
  menuRenameAria: "Mudar nome",
  menuFollow: "Seguir",
  menuUnfollow: "Parar de seguir",
  infoLastSeen: "Visto pela última vez: {t}",
  infoDistance: "A {d} de distância",
  statusOnline: "Online",
  statusNoSignal: "Sem sinal",
};

/** Exported so scripts/i18n-to-arb.ts can export EVERY language to the native
 *  apps' ARB files. At runtime only DICTS[lang] is ever read. */
export const DICTS: Record<Lang, Record<Key, string>> = { de, en, es, it, fr, pt };

/** Translate a key, replacing {name} placeholders from params. */
export function t(key: Key, params?: Record<string, string | number>): string {
  let s: string = DICTS[lang][key] ?? de[key];
  if (params) {
    for (const p in params) s = s.split(`{${p}}`).join(String(params[p]));
  }
  return s;
}

/** Fill the static HTML: <title>, <html lang>, and any [data-i18n]/[data-i18n-aria]. */
export function applyStaticI18n(): void {
  document.documentElement.lang = lang;
  document.title = t("title");
  document.querySelectorAll<HTMLElement>("[data-i18n]").forEach((el) => {
    el.textContent = t(el.dataset.i18n as Key);
  });
  document.querySelectorAll<HTMLElement>("[data-i18n-aria]").forEach((el) => {
    el.setAttribute("aria-label", t(el.dataset.i18nAria as Key));
  });
}

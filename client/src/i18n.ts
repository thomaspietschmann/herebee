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
  youSuffix: "(du)",
  linkCopied: "Link kopiert",
  shareTitle: "Raum teilen",
  shareBody:
    "Wer diesen Link öffnet, tritt dem Raum bei und sieht die Live-Standorte. Der Link <strong>ist</strong> der Schlüssel — teile ihn bewusst.",
  copy: "Kopieren",
  welcomeTitle: "Willkommen bei HereBee",
  welcomeIntro: "Du bist in einem privaten Raum. Alle mit diesem Link finden sich hier live auf der Karte.",
  welcomeFact1:
    "<strong>Nur zuschauen ist okay.</strong> Du musst deinen Standort nicht teilen — dann siehst du nur die anderen.",
  welcomeFact2:
    "<strong>Standort teilen:</strong> Tippe unten auf <em>„Standort teilen“</em>. Danach sehen <strong>alle im Raum</strong> deinen Live-Standort — Ende-zu-Ende-verschlüsselt, nichts wird gespeichert.",
  welcomeFact3:
    "<strong>Jederzeit stoppen:</strong> Der Button wird zu <em>„Teilen stoppen“</em> — ein Tipp, und du bist wieder unsichtbar.",
  welcomeCta: "Los geht's",
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
  infoFact3: "Es gibt <strong>keine Datenbank und keine Logs</strong>; Räume leben nur, solange jemand da ist.",
  infoFact4:
    "Der HereBee-Server (Relay und selbst gehostete Karten) sieht deine <strong>IP</strong> für die Dauer der Verbindung — nicht gespeichert, und keine fremden Karten- oder CDN-Dienste. Die eigene IP lässt sich im Browser generell nicht verbergen.",
  infoFact5: "Wer den vollständigen Link hat, sieht den Raum. Teile ihn nur mit Vertrauten.",
  mapCredits: "Karte: {pm} © {osm}-Mitwirkende",
  noGeo: "Dieses Gerät kann keinen Standort teilen",
  geoDenied: "Standortfreigabe wurde abgelehnt",
  geoUnavailable: "Standort nicht verfügbar",
  fatalInvalidRoom: "Ungültiger Raum-Link",
  fatalRejected: "Verbindung abgelehnt",
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
  youSuffix: "(you)",
  linkCopied: "Link copied",
  shareTitle: "Share room",
  shareBody:
    "Anyone who opens this link joins the room and sees the live locations. The link <strong>is</strong> the key — share it deliberately.",
  copy: "Copy",
  welcomeTitle: "Welcome to HereBee",
  welcomeIntro: "You're in a private room. Everyone with this link meets here live on the map.",
  welcomeFact1:
    "<strong>Just watching is fine.</strong> You don't have to share your location — then you only see the others.",
  welcomeFact2:
    "<strong>Share location:</strong> Tap <em>“Share location”</em> below. Then <strong>everyone in the room</strong> sees your live location — end-to-end encrypted, nothing is stored.",
  welcomeFact3:
    "<strong>Stop anytime:</strong> The button turns into <em>“Stop sharing”</em> — one tap and you're invisible again.",
  welcomeCta: "Let's go",
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
  infoFact3: "There is <strong>no database and no logs</strong>; rooms exist only while someone is present.",
  infoFact4:
    "The HereBee server (relay and self-hosted maps) sees your <strong>IP</strong> for the duration of the connection — not stored, and no third-party map or CDN services. A browser generally can't hide your IP.",
  infoFact5: "Anyone with the full link can see the room. Share it only with people you trust.",
  mapCredits: "Map: {pm} © {osm} contributors",
  noGeo: "This device can't share a location",
  geoDenied: "Location permission denied",
  geoUnavailable: "Location unavailable",
  fatalInvalidRoom: "Invalid room link",
  fatalRejected: "Connection rejected",
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
  youSuffix: "(tú)",
  linkCopied: "Enlace copiado",
  shareTitle: "Compartir sala",
  shareBody:
    "Quien abra este enlace entra en la sala y ve las ubicaciones en vivo. El enlace <strong>es</strong> la clave: compártelo con cuidado.",
  copy: "Copiar",
  welcomeTitle: "Bienvenido a HereBee",
  welcomeIntro: "Estás en una sala privada. Todos los que tengan este enlace se encuentran aquí en vivo en el mapa.",
  welcomeFact1:
    "<strong>Solo mirar está bien.</strong> No tienes que compartir tu ubicación: así solo ves a los demás.",
  welcomeFact2:
    "<strong>Compartir ubicación:</strong> Toca <em>«Compartir ubicación»</em> abajo. Entonces <strong>todos en la sala</strong> ven tu ubicación en vivo: cifrada de extremo a extremo, no se guarda nada.",
  welcomeFact3:
    "<strong>Detente cuando quieras:</strong> El botón cambia a <em>«Dejar de compartir»</em>: un toque y vuelves a ser invisible.",
  welcomeCta: "¡Vamos!",
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
  infoFact3: "No hay <strong>ni base de datos ni registros</strong>; las salas existen solo mientras hay alguien.",
  infoFact4:
    "El servidor de HereBee (relay y mapas alojados por nosotros mismos) ve tu <strong>IP</strong> mientras dura la conexión: no se guarda y no hay servicios de mapas o CDN de terceros. El navegador no puede ocultar tu IP en general.",
  infoFact5: "Cualquiera con el enlace completo ve la sala. Compártelo solo con personas de confianza.",
  mapCredits: "Mapa: {pm} © colaboradores de {osm}",
  noGeo: "Este dispositivo no puede compartir la ubicación",
  geoDenied: "Se denegó el permiso de ubicación",
  geoUnavailable: "Ubicación no disponible",
  fatalInvalidRoom: "Enlace de sala no válido",
  fatalRejected: "Conexión rechazada",
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
  youSuffix: "(tu)",
  linkCopied: "Link copiato",
  shareTitle: "Condividi stanza",
  shareBody:
    "Chi apre questo link entra nella stanza e vede le posizioni in tempo reale. Il link <strong>è</strong> la chiave: condividilo con attenzione.",
  copy: "Copia",
  welcomeTitle: "Benvenuto su HereBee",
  welcomeIntro: "Sei in una stanza privata. Tutti quelli che hanno questo link si ritrovano qui, live sulla mappa.",
  welcomeFact1:
    "<strong>Solo guardare va bene.</strong> Non devi condividere la tua posizione: così vedi solo gli altri.",
  welcomeFact2:
    "<strong>Condividi posizione:</strong> Tocca <em>«Condividi posizione»</em> in basso. Poi <strong>tutti nella stanza</strong> vedono la tua posizione in tempo reale: cifrata end-to-end, non viene memorizzato nulla.",
  welcomeFact3:
    "<strong>Fermati quando vuoi:</strong> Il pulsante diventa <em>«Interrompi condivisione»</em>: un tocco e torni invisibile.",
  welcomeCta: "Iniziamo",
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
  infoFact3: "Non c'è <strong>alcun database né log</strong>; le stanze esistono solo finché c'è qualcuno.",
  infoFact4:
    "Il server di HereBee (relay e mappe self-hosted) vede il tuo <strong>IP</strong> per la durata della connessione: non viene memorizzato e non ci sono servizi di mappe o CDN di terze parti. Il browser in generale non può nascondere il tuo IP.",
  infoFact5: "Chiunque abbia il link completo vede la stanza. Condividilo solo con persone fidate.",
  mapCredits: "Mappa: {pm} © contributori di {osm}",
  noGeo: "Questo dispositivo non può condividere la posizione",
  geoDenied: "Autorizzazione alla posizione negata",
  geoUnavailable: "Posizione non disponibile",
  fatalInvalidRoom: "Link della stanza non valido",
  fatalRejected: "Connessione rifiutata",
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
    "<strong>Juste regarder, c'est permis.</strong> Tu n'as pas à partager ta position — dans ce cas, tu vois seulement les autres.",
  welcomeFact2:
    "<strong>Partager ma position :</strong> Touche <em>« Partager ma position »</em> en bas. Ensuite, <strong>tout le monde dans le salon</strong> voit ta position en direct — chiffrée de bout en bout, rien n'est conservé.",
  welcomeFact3:
    "<strong>Arrête quand tu veux :</strong> Le bouton devient <em>« Arrêter le partage »</em> — une touche et tu es de nouveau invisible.",
  welcomeCta: "C'est parti",
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
  infoFact3: "Il n'y a <strong>aucune base de données ni journaux</strong> ; les salons n'existent que tant que quelqu'un est présent.",
  infoFact4:
    "Le serveur HereBee (relais et cartes auto-hébergées) voit ton <strong>IP</strong> pendant la durée de la connexion — non conservée, et aucun service de cartes ou CDN tiers. Un navigateur ne peut généralement pas masquer ton IP.",
  infoFact5: "Quiconque possède le lien complet voit le salon. Ne le partage qu'avec des personnes de confiance.",
  mapCredits: "Carte : {pm} © contributeurs d'{osm}",
  noGeo: "Cet appareil ne peut pas partager de position",
  geoDenied: "Autorisation de localisation refusée",
  geoUnavailable: "Position indisponible",
  fatalInvalidRoom: "Lien de salon invalide",
  fatalRejected: "Connexion refusée",
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
  youSuffix: "(tu)",
  linkCopied: "Link copiado",
  shareTitle: "Partilhar sala",
  shareBody:
    "Quem abrir este link entra na sala e vê as localizações em tempo real. O link <strong>é</strong> a chave — partilha-o com cuidado.",
  copy: "Copiar",
  welcomeTitle: "Bem-vindo ao HereBee",
  welcomeIntro: "Estás numa sala privada. Todos os que tiverem este link encontram-se aqui, ao vivo no mapa.",
  welcomeFact1:
    "<strong>Só observar está bem.</strong> Não tens de partilhar a tua localização — assim vês apenas os outros.",
  welcomeFact2:
    "<strong>Partilhar localização:</strong> Toca em <em>«Partilhar localização»</em> abaixo. Depois <strong>todos na sala</strong> veem a tua localização em tempo real — cifrada de ponta a ponta, nada é guardado.",
  welcomeFact3:
    "<strong>Para quando quiseres:</strong> O botão muda para <em>«Parar de partilhar»</em> — um toque e ficas invisível de novo.",
  welcomeCta: "Vamos",
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
  infoFact3: "Não há <strong>base de dados nem registos</strong>; as salas existem apenas enquanto alguém estiver presente.",
  infoFact4:
    "O servidor do HereBee (relay e mapas alojados por nós) vê o teu <strong>IP</strong> durante a ligação — não é guardado e não há serviços de mapas ou CDN de terceiros. O navegador em geral não consegue ocultar o teu IP.",
  infoFact5: "Qualquer pessoa com o link completo vê a sala. Partilha-o apenas com pessoas de confiança.",
  mapCredits: "Mapa: {pm} © colaboradores do {osm}",
  noGeo: "Este dispositivo não consegue partilhar a localização",
  geoDenied: "Permissão de localização recusada",
  geoUnavailable: "Localização indisponível",
  fatalInvalidRoom: "Link de sala inválido",
  fatalRejected: "Ligação recusada",
};

const DICTS: Record<Lang, Record<Key, string>> = { de, en, es, it, fr, pt };

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

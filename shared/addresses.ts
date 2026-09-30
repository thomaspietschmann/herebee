export const ADDRESSES_SOURCE = "addresses";
export const ADDRESSES_MINZOOM = 15;

interface AddressFlavor {
  address_label: string;
  address_label_halo: string;
  italic?: string;
}

export function addressLayer(flavor: AddressFlavor) {
  return {
    id: "address_label",
    type: "symbol" as const,
    source: ADDRESSES_SOURCE,
    "source-layer": "addresses",
    minzoom: ADDRESSES_MINZOOM,
    layout: {
      "symbol-placement": "point" as const,
      "text-font": [flavor.italic || "Noto Sans Italic"],
      "text-field": ["get", "housenumber"],
      "text-size": 12,
    },
    paint: {
      "text-color": flavor.address_label,
      "text-halo-color": flavor.address_label_halo,
      "text-halo-width": 1,
    },
  };
}

export function withAddressLayer<L extends { id: string }>(base: L[], flavor: AddressFlavor): L[] {
  const layer = addressLayer(flavor) as unknown as L;
  const at = base.findIndex((l) => l.id === "address_label");
  if (at < 0) return [...base, layer];
  return [...base.slice(0, at), layer, ...base.slice(at + 1)];
}

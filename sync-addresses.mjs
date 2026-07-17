import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const raiz = dirname(fileURLToPath(import.meta.url));
const chainId = process.argv[2];

if (!chainId) {
  console.log("uso: node sync-addresses.mjs <chainId>   (ex: 260 | 37111)");
  process.exit(1);
}

const REDES = {
  37111: "lens-testnet",
  260: "anvil",
  31337: "anvil",
};

const leerJson = (ruta, fallback) => {
  if (!existsSync(ruta)) return fallback;
  return JSON.parse(readFileSync(ruta, "utf8"));
};

const escribirJson = (ruta, datos) => {
  writeFileSync(ruta, JSON.stringify(datos, null, 2) + "\n");
  console.log("escrito:", ruta);
};

const allPath = join(raiz, "contracts/deployments", `all.${chainId}.json`);
const gandaPath = join(raiz, "contracts/deployments", `ganda.${chainId}.json`);

const all = leerJson(allPath, null);
if (!all) {
  console.log("falta", allPath, "— lanza DeployAll primero");
  process.exit(1);
}
const ganda = leerJson(gandaPath, null);
if (!ganda) {
  console.log("aviso: falta", gandaPath, "— solo sincronizo matroid");
}

if (ganda) {
  const direccionesPath = join(raiz, "../ganda/src/app/lib/direcciones.json");
  const direcciones = leerJson(direccionesPath, {});
  direcciones[chainId] = {
    games: ganda.games,
    hub: ganda.hub,
    score: ganda.score,
    council: ganda.council,
    blacklist: ganda.blacklist,
    paymaster: ganda.paymaster,
    accessControl: ganda.accessControl,
    identityRegistry: ganda.identityRegistry ?? all.identityRegistry,
    mona: all.mona,
  };
  escribirJson(direccionesPath, direcciones);

  const yamlPath = join(raiz, "subgraph/ganda/subgraph.yaml");
  if (existsSync(yamlPath)) {
    const porNombre = {
      GandaGames: ganda.games,
      GandaHub: ganda.hub,
      GandaScore: ganda.score,
      GandaCouncil: ganda.council,
      GandaBlacklist: ganda.blacklist,
      GandaPaymaster: ganda.paymaster,
    };
    const lineas = readFileSync(yamlPath, "utf8").split("\n");
    let actual = null;
    for (let i = 0; i < lineas.length; i++) {
      const nombre = lineas[i].match(/^    name: (\w+)$/);
      if (nombre) actual = nombre[1];
      if (actual && porNombre[actual] && /^      address: "0x/.test(lineas[i])) {
        lineas[i] = `      address: "${porNombre[actual]}"`;
      }
    }
    writeFileSync(yamlPath, lineas.join("\n"));
    console.log("escrito:", yamlPath);
  }

  const red = REDES[chainId];
  if (red) {
    const redesGandaPath = join(raiz, "subgraph/ganda/networks.json");
    const redesGanda = leerJson(redesGandaPath, {});
    const previa = redesGanda[red] ?? {};
    const conBloque = (nombre, address) => ({
      address,
      startBlock: previa[nombre]?.startBlock ?? 0,
    });
    redesGanda[red] = {
      GandaGames: conBloque("GandaGames", ganda.games),
      GandaHub: conBloque("GandaHub", ganda.hub),
      GandaScore: conBloque("GandaScore", ganda.score),
      GandaCouncil: conBloque("GandaCouncil", ganda.council),
      GandaBlacklist: conBloque("GandaBlacklist", ganda.blacklist),
      GandaPaymaster: conBloque("GandaPaymaster", ganda.paymaster),
    };
    escribirJson(redesGandaPath, redesGanda);
  }
}

const red = REDES[chainId];
if (red) {
  const redesMatroidPath = join(raiz, "subgraph/matroid/networks.json");
  const redesMatroid = leerJson(redesMatroidPath, {});
  const previa = redesMatroid[red] ?? {};
  const conBloque = (nombre, address) => ({
    address,
    startBlock: previa[nombre]?.startBlock ?? 0,
  });
  redesMatroid[red] = {
    MatroidRegistry: conBloque("MatroidRegistry", all.matroidRegistry),
    MatroidKit: conBloque("MatroidKit", all.matroidKit),
    Treasury: conBloque("Treasury", all.treasury),
    SlashingCouncil: conBloque("SlashingCouncil", all.slashingCouncil),
    GlobalStakingPool: conBloque("GlobalStakingPool", all.globalStakingPool),
    MatroidAnonGovernance: conBloque(
      "MatroidAnonGovernance",
      all.matroidAnonGovernance,
    ),
    IdentityRegistry: conBloque("IdentityRegistry", all.identityRegistry),
    BalancePool: conBloque("BalancePool", all.matroidBalancePool),
    SponsorVault: conBloque("SponsorVault", all.sponsorVault),
  };
  escribirJson(redesMatroidPath, redesMatroid);
}

console.log("");
console.log(
  "bloque para la interfaz matroid (pegar en CORE_CONTRACT_ADDRESSES[" +
    chainId +
    "]):",
);
console.log(`  {
    Mona: "${all.mona}",
    StakingFactory: "${all.stakingFactory}",
    SignalRegistry: "${all.matroidRegistry}",
    SignalKit: "${all.matroidKit}",
    SignalScorer: "${all.scorer}",
    GlobalStakingPool: "${all.globalStakingPool}",
    Treasury: "${all.treasury}",
    SlashingCouncil: "${all.slashingCouncil}",
    MatroidAnonGovernance: "${all.matroidAnonGovernance}",
    IdentityRegistry: "${all.identityRegistry}",
    BalancePool: "${all.matroidBalancePool}",
  }`);
console.log("");
console.log(
  "listo. chains no tocadas:",
  Object.values(REDES)
    .filter((r) => r !== red)
    .join(", "),
);

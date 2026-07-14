import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  ClaimerUpdated as ClaimerUpdatedEvent,
  FlowRecorded as FlowRecordedEvent,
  MatroidRegistry,
  ProjectMetadataUpdated as ProjectMetadataUpdatedEvent,
  ProjectPoolsCreated as ProjectPoolsCreatedEvent,
  ProjectRegistered as ProjectRegisteredEvent,
  RewardSplitsUpdated as RewardSplitsUpdatedEvent,
} from "../generated/MatroidRegistry/MatroidRegistry";
import {
  Project,
  ProjectPoolERC20,
  ProjectPoolNFT,
  ProjectPoolsCreated,
  Global,
  TokenFlow,
} from "../generated/schema";
import {
  ProjectMetadata as MetadataTemplate,
  ProjectNFTStakingPool,
  ProjectStakingPool,
} from "../generated/templates";
import { ProjectStakingPool as ProjectStakingPoolContract } from "../generated/templates/ProjectStakingPool/ProjectStakingPool";
import { ProjectNFTStakingPool as ProjectNFTStakingPoolContract } from "../generated/templates/ProjectNFTStakingPool/ProjectNFTStakingPool";

export function handleClaimerUpdated(event: ClaimerUpdatedEvent): void {
  let proyecto = Project.load(event.params.project);
  if (proyecto) {
    let admins = proyecto.admins;
    if (!admins) {
      admins = new Array<Bytes>();
    }
    if (event.params.allowed) {
      admins.push(event.params.claimer);
      proyecto.admins = admins;
    } else {
      let newAdmins = new Array<Bytes>();
      for (let i = 0; i < admins.length; i++) {
        if (!admins[i].equals(event.params.claimer)) {
          newAdmins.push(admins[i]);
        }
      }

      proyecto.admins = newAdmins;
    }

    proyecto.save();
  }
}

export function handleFlowRecorded(event: FlowRecordedEvent): void {
  let entity = new TokenFlow(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );

  entity.user = event.params.user;
  entity.token = event.params.token;
  entity.amount = event.params.amount;
  entity.project = event.params.project;
  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let proyecto = Project.load(event.params.project);
  if (proyecto) {
    if (event.params.isIn) {
      let ins = proyecto.monaIn;
      if (!ins) {
        ins = [];
      }
      ins.push(entity.id);

      proyecto.monaIn = ins;
    } else {
      let outs = proyecto.monaOut;
      if (!outs) {
        outs = [];
      }
      outs.push(entity.id);
      proyecto.monaOut = outs;
    }

    proyecto.save();
  }
}

export function handleProjectPoolsCreated(
  event: ProjectPoolsCreatedEvent,
): void {
  let poolsEntity = new ProjectPoolsCreated(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  poolsEntity.project = event.params.project;
  poolsEntity.erc20Pool = event.params.erc20Pool;
  poolsEntity.nftPool = event.params.nftPool;
  poolsEntity.blockNumber = event.block.number;
  poolsEntity.blockTimestamp = event.block.timestamp;
  poolsEntity.transactionHash = event.transaction.hash;
  poolsEntity.save();

  let proyecto = Project.load(event.params.project);
  if (proyecto) {
    let erc20Pool = ProjectPoolERC20.load(event.params.erc20Pool);
    if (!erc20Pool) {
      erc20Pool = new ProjectPoolERC20(event.params.erc20Pool);
      erc20Pool.project = proyecto.id;
      erc20Pool.totalStaked = BigInt.fromI32(0);
      erc20Pool.rewardNotifiedTotal = BigInt.fromI32(0);
      erc20Pool.rewardTokens = [];
      erc20Pool.claims = [];
      erc20Pool.stakerCount = 0;
      erc20Pool.stakers = [];
    }

    let nftPool = ProjectPoolNFT.load(event.params.nftPool);
    if (!nftPool) {
      nftPool = new ProjectPoolNFT(event.params.nftPool);
      nftPool.project = proyecto.id;
      nftPool.totalWeight = BigInt.fromI32(0);
      nftPool.whitelistCount = 0;
      nftPool.whitelistedNfts = [];
      nftPool.rewardNotifiedTotal = BigInt.fromI32(0);
      nftPool.rewardTokens = [];
      nftPool.claims = [];
      nftPool.stakerCount = 0;
      nftPool.stakers = [];
    }

    let erc20Contract = ProjectStakingPoolContract.bind(event.params.erc20Pool);
    let erc20Mona = erc20Contract.try_mona();
    if (!erc20Mona.reverted) {
      let tokens = erc20Pool.rewardTokens;
      if (!tokens) {
        tokens = [];
      }
      tokens.push(erc20Mona.value);
      erc20Pool.rewardTokens = tokens;
    }

    let nftContract = ProjectNFTStakingPoolContract.bind(event.params.nftPool);
    let nftMona = nftContract.try_mona();
    if (!nftMona.reverted) {
      let tokens = nftPool.rewardTokens;
      if (!tokens) {
        tokens = [];
      }
      tokens.push(nftMona.value);
      nftPool.rewardTokens = tokens;
    }

    erc20Pool.save();
    nftPool.save();

    proyecto.erc20Pool = erc20Pool.id;
    proyecto.nftPool = nftPool.id;

    proyecto.save();

    ProjectStakingPool.create(event.params.erc20Pool);
    ProjectNFTStakingPool.create(event.params.nftPool);
  }
}

export function handleProjectRegistered(event: ProjectRegisteredEvent): void {
  let contract = MatroidRegistry.bind(event.address);
  let proyecto = new Project(event.params.project);
  proyecto.blockNumber = event.block.number;
  proyecto.blockTimestamp = event.block.timestamp;
  proyecto.transactionHash = event.transaction.hash;

  let projectstats = contract.getProject(event.params.project);
  proyecto.registeredAt = projectstats.registeredAt;
  proyecto.erc20Pool = projectstats.projectPool;
  proyecto.nftPool = projectstats.projectNftPool;
  proyecto.globalSplitBps = projectstats.globalSplitBps;
  proyecto.projectErc20SplitBps = projectstats.projectErc20SplitBps;
  proyecto.projectNftSplitBps = projectstats.projectNftSplitBps;
  proyecto.monaTxCount = projectstats.monaTxCount;
  proyecto.monaUniqueUsers = projectstats.monaUniqueUsers;
  proyecto.admins = [];

  let uri = event.params.metadata;
  proyecto.metadataUri = uri;
  if (uri.startsWith("ipfs://")) {
    let ipfsHash = uri.split("/").pop();
    if (ipfsHash != null && ipfsHash.length > 0) {
      proyecto.metadata = ipfsHash;
      MetadataTemplate.create(ipfsHash);
    }
  }

  proyecto.save();

  let global = Global.load(Bytes.fromUTF8("global"));
  if (global) {
    let projects = global.projects;
    if (!projects) {
      projects = [];
    }
    let exists = false;
    for (let i = 0; i < projects.length; i++) {
      if (projects[i].equals(proyecto.id)) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      projects.push(proyecto.id);
      global.projects = projects;
      global.save();
    }
  }
}

export function handleProjectMetadataUpdated(
  event: ProjectMetadataUpdatedEvent,
): void {
  let proyecto = Project.load(event.params.project);
  if (proyecto) {
    let uri = event.params.metadata;
    proyecto.metadataUri = uri;
    if (uri.startsWith("ipfs://")) {
      let ipfsHash = uri.split("/").pop();
      if (ipfsHash != null && ipfsHash.length > 0) {
        proyecto.metadata = ipfsHash;
        MetadataTemplate.create(ipfsHash);
      }
    }
    proyecto.save();
  }
}

export function handleRewardSplitsUpdated(
  event: RewardSplitsUpdatedEvent,
): void {
  let proyecto = Project.load(event.params.project);
  if (proyecto) {
    proyecto.globalSplitBps = event.params.globalSplitBps;
    proyecto.projectErc20SplitBps = event.params.projectErc20SplitBps;
    proyecto.projectNftSplitBps = event.params.projectNftSplitBps;
    proyecto.save();
  }
}

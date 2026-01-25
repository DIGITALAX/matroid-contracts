import { Bytes, DataSourceContext } from "@graphprotocol/graph-ts";
import {
  ProjectPoolCreated as ProjectPoolCreatedEvent,
  ProjectPoolsCreated as ProjectPoolsCreatedEvent,
} from "../generated/StakingFactory/StakingFactory";
import {  ProjectPoolsCreated } from "../generated/schema";
import { ProjectPoolERC20, ProjectPoolNFT } from "../generated/templates";

export function handleProjectPoolsCreated(
  event: ProjectPoolsCreatedEvent,
): void {
  let entity = new ProjectPoolsCreated(event.params.project as Bytes);
  entity.project = event.params.project;
  entity.erc20Pool = event.params.erc20Pool;
  entity.nftPool = event.params.nftPool;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  let context = new DataSourceContext();
  context.setBytes("project", event.params.project);
  ProjectPoolERC20.createWithContext(event.params.erc20Pool, context);
  ProjectPoolNFT.createWithContext(event.params.nftPool, context);

  entity.save();
}

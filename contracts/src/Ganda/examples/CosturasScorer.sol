// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// Exemplo mínimo de "scorer" de um jogo integrado ao Ganda.
/// O jogo "Costuras de Retaguardia" deploya isto, e o dono registra este
/// endereço como scorer no GandaGames (publishGame / pushVersion). A partir
/// daí, SÓ este contrato pode reportar notas e mover MONA em nome do jogo.
///
/// A lógica interna do jogo (o que vale um ponto) é decisão do jogo — aqui é
/// uma base trivial: o dono reporta pontos por jogador. Trocar `onlyOwner`
/// pela mecânica real do jogo é o único trabalho de integração.

interface IGandaScore {
    function submitScore(uint256 gameId, address player, uint256 points) external;
    function submitScoreAnon(uint256 gameId, bytes32 playerNullifier, uint256 points) external;
}

interface IGandaHub {
    function monaIn(uint256 gameId, address player, uint256 amount, address destination) external;
    function monaOut(uint256 gameId, address recipient, uint256 amount) external;
}

contract CosturasScorer {
    address public owner;
    uint256 public gameId;
    IGandaScore public immutable score;
    IGandaHub public immutable hub;

    event OwnerTransferred(address indexed previous, address indexed next);
    event GameIdSet(uint256 gameId);
    event PointsReported(address indexed player, uint256 points);
    event PointsReportedAnon(bytes32 indexed playerNullifier, uint256 points);

    error NotOwner();
    error GameIdNotSet();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address scoreAddress, address hubAddress) {
        if (scoreAddress == address(0) || hubAddress == address(0)) revert ZeroAddress();
        owner = msg.sender;
        score = IGandaScore(scoreAddress);
        hub = IGandaHub(hubAddress);
        emit OwnerTransferred(address(0), msg.sender);
    }

    /// O dono chama isto UMA vez, com o gameId que o GandaGames devolveu ao
    /// publicar o jogo apontando este contrato como scorer.
    function setGameId(uint256 newGameId) external onlyOwner {
        gameId = newGameId;
        emit GameIdSet(newGameId);
    }

    function transferOwner(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit OwnerTransferred(owner, next);
        owner = next;
    }

    /// Reporta a nota de um jogador público (por endereço).
    function reportScore(address player, uint256 points) external onlyOwner {
        if (gameId == 0) revert GameIdNotSet();
        score.submitScore(gameId, player, points);
        emit PointsReported(player, points);
    }

    /// Reporta a nota de um jogador anônimo — o nullifier de claim que o
    /// jogador (com chip) calculou para a época atual, ver llms.txt.
    function reportScoreAnon(bytes32 playerNullifier, uint256 points) external onlyOwner {
        if (gameId == 0) revert GameIdNotSet();
        score.submitScoreAnon(gameId, playerNullifier, points);
        emit PointsReportedAnon(playerNullifier, points);
    }

    /// Entrada de MONA pelos trilhos do Ganda (o jogador aprovou MONA ao
    /// MatroidRegistry antes). `destination` = para onde vai o resto após os
    /// splits, ex.: o cofre de prêmios do próprio jogo.
    function recordIn(address player, uint256 amount, address destination) external onlyOwner {
        if (gameId == 0) revert GameIdNotSet();
        hub.monaIn(gameId, player, amount, destination);
    }

    /// Pagamento de prêmio: o jogo aprovou MONA ao GandaHub antes; o Hub
    /// registra a saída no matroid e entrega o valor inteiro ao recipient.
    function payPrize(address recipient, uint256 amount) external onlyOwner {
        if (gameId == 0) revert GameIdNotSet();
        hub.monaOut(gameId, recipient, amount);
    }
}

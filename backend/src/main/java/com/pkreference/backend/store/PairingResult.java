package com.pkreference.backend.store;

import com.pkreference.backend.model.Events.Pairing;

/** How a Limitless match ended. */
public enum PairingResult {
    /** player1 won. */
    P1,
    /** player2 won. */
    P2,
    TIE,
    /** Both players lost (winner -1). */
    DOUBLE_LOSS,
    /** player1 had no opponent and won. */
    BYE,
    /** player1 had no opponent and lost: Limitless's automatic loss for lateness. */
    NO_SHOW,
    /** No winner yet (an event in progress), or a winner that's neither player. */
    UNKNOWN;

    /** Whether both players played it: a match to count for or against them. */
    public boolean wasPlayed() {
        return this == P1 || this == P2 || this == TIE || this == DOUBLE_LOSS;
    }

    /**
     * Reads Limitless's {@code winner} field, which holds a username, "0" (a tie) or "-1" (both
     * lost). With no second player it's a bye when player 1 is the winner, otherwise a no-show.
     * Storing the result as one word means every query can say {@code result in ('P1', 'P2', ...)}
     * instead of repeating these rules in SQL.
     */
    public static PairingResult of(Pairing p) {
        String winner = p.winner();
        boolean opponent = p.player2() != null && !p.player2().isBlank();
        if (!opponent) {
            if (winner != null && winner.equals(p.player1())) return BYE;
            return NO_SHOW;
        }
        if (winner == null) return UNKNOWN;
        if (winner.equals("0")) return TIE;
        if (winner.equals("-1")) return DOUBLE_LOSS;
        if (winner.equals(p.player1())) return P1;
        if (winner.equals(p.player2())) return P2;
        return UNKNOWN;
    }
}

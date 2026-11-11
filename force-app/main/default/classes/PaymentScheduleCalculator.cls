/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : PaymentScheduleCalculator
 * Author          : Arelia
 * Created Date    : Nov 3, 2026
 * Last Modified By: Arelia
 * Last Modified On: Nov 3, 2026
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * Allocates the current project balance across unpaid terms.
 * Recorded paid amounts are never derived from percentages or a new budget.
 */
public class PaymentScheduleCalculator {
    public class Line {
        public Id termId;
        public Decimal percentage;
        public Boolean paid;
        public Decimal paidAmount;
        public Line(Id termId, Decimal percentage, Boolean paid, Decimal paidAmount) {
            this.termId = termId;
            this.percentage = percentage;
            this.paid = paid;
            this.paidAmount = paidAmount;
        }
    }

    public static Map<Id, Decimal> allocate(Decimal budget, List<Line> lines) {
        Map<Id, Decimal> amounts = new Map<Id, Decimal>();
        Decimal paid = 0;
        Decimal weight = 0;
        Boolean complete = budget != null && budget >= 0;
        for (Line line : lines) {
            amounts.put(line.termId, null);
            if (line.paid == true) {
                if (line.paidAmount == null || line.paidAmount < 0) {
                    complete = false;
                } else {
                    Decimal actual = line.paidAmount.setScale(2);
                    amounts.put(line.termId, actual);
                    paid += actual;
                }
            } else if (line.percentage == null || line.percentage < 0) {
                complete = false;
            } else {
                weight += line.percentage;
            }
        }
        // Missing historical amounts must not be replaced with today's estimate.
        if (!complete || weight <= 0) return amounts;
        Decimal balance = budget - paid;
        if (balance < 0) balance = 0;
        balance = balance.setScale(2, RoundingMode.HALF_UP);
        Decimal cumulativeWeight = 0;
        Decimal allocated = 0;
        for (Line line : lines) {
            if (line.paid == true) continue;
            cumulativeWeight += line.percentage;
            // Cumulative rounding ensures that all unpaid lines total exactly
            // the remaining balance, including the final paise.
            Decimal cumulativeAmount = (balance * cumulativeWeight / weight).setScale(2, RoundingMode.HALF_UP);
            amounts.put(line.termId, cumulativeAmount - allocated);
            allocated = cumulativeAmount;
        }
        return amounts;
    }
}
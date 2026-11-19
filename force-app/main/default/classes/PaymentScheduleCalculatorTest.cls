/**
 * @description Unit tests for PaymentScheduleCalculator.
 * Validates payment allocation, historical paid amounts,
 * remaining balances, invalid inputs, and rounding.
 */
@IsTest
private class PaymentScheduleCalculatorTest {

    private static final Decimal ZERO_AMOUNT = 0.00;
    private static final Decimal BUDGET = 100000.00;

    /**
     * @description Creates an allocation line.
     * @param termId Unique identifier for the payment term.
     * @param percentage Allocation weight.
     * @param isPaid Indicates whether the term is paid.
     * @param paidAmount Recorded historical payment amount.
     * @return Payment schedule line.
     */
    private static PaymentScheduleCalculator.Line createLine(
        Id termId,
        Decimal percentage,
        Boolean isPaid,
        Decimal paidAmount
    ) {
        return new PaymentScheduleCalculator.Line(
            termId,
            percentage,
            isPaid,
            paidAmount
        );
    }

    /**
     * @description Verifies allocation across unpaid terms
     * using their respective percentages.
     */
    @IsTest
    static void testAllocateAllUnpaidTerms() {
        Id firstId = UserInfo.getUserId();
        Id secondId = UserInfo.getOrganizationId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(firstId, 40, false, null),
                createLine(secondId, 60, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            2,
            amounts.size(),
            'Both unpaid terms must be included.'
        );
        System.assertEquals(
            40000.00,
            amounts.get(firstId),
            'First term must receive 40% of the budget.'
        );
        System.assertEquals(
            60000.00,
            amounts.get(secondId),
            'Second term must receive 60% of the budget.'
        );
    }

    /**
     * @description Confirms historical paid amounts are
     * preserved and only the remaining balance is allocated.
     */
    @IsTest
    static void testAllocateWithPaidTerm() {
        Id paidId = UserInfo.getUserId();
        Id unpaidId = UserInfo.getOrganizationId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(paidId, 30, true, 25000.00),
                createLine(unpaidId, 70, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            25000.00,
            amounts.get(paidId),
            'Recorded paid amount must remain unchanged.'
        );
        System.assertEquals(
            75000.00,
            amounts.get(unpaidId),
            'Unpaid term must receive the remaining balance.'
        );
    }

    /**
     * @description Ensures excess historical payments
     * do not produce negative unpaid allocations.
     */
    @IsTest
    static void testPaidAmountExceedsBudget() {
        Id paidId = UserInfo.getUserId();
        Id unpaidId = UserInfo.getOrganizationId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(paidId, 50, true, 120000.00),
                createLine(unpaidId, 50, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            120000.00,
            amounts.get(paidId),
            'Historical payment must be retained.'
        );
        System.assertEquals(
            ZERO_AMOUNT,
            amounts.get(unpaidId),
            'Remaining allocation must not be negative.'
        );
    }

    /**
     * @description Ensures a missing historical paid
     * amount prevents recalculation.
     */
    @IsTest
    static void testMissingPaidAmount() {
        Id paidId = UserInfo.getUserId();
        Id unpaidId = UserInfo.getOrganizationId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(paidId, 40, true, null),
                createLine(unpaidId, 60, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            2,
            amounts.size(),
            'Both terms must remain in the result.'
        );
        System.assertEquals(
            null,
            amounts.get(paidId),
            'Missing historical amount must remain null.'
        );
        System.assertEquals(
            null,
            amounts.get(unpaidId),
            'Allocation must stop when paid amount is missing.'
        );
    }

    /**
     * @description Validates rejection of negative
     * historical payment amounts.
     */
    @IsTest
    static void testNegativePaidAmount() {
        Id paidId = UserInfo.getUserId();
        Id unpaidId = UserInfo.getOrganizationId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(paidId, 40, true, -100.00),
                createLine(unpaidId, 60, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            null,
            amounts.get(paidId),
            'Negative historical payment must be rejected.'
        );
        System.assertEquals(
            null,
            amounts.get(unpaidId),
            'Invalid historical payment must stop allocation.'
        );
    }

    /**
     * @description Verifies missing budget prevents
     * payment allocations.
     */
    @IsTest
    static void testNullBudget() {
        Id termId = UserInfo.getUserId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(termId, 100, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(null, lines);
        Test.stopTest();

        System.assertEquals(
            1,
            amounts.size(),
            'Term must remain in the result.'
        );
        System.assertEquals(
            null,
            amounts.get(termId),
            'Null budget must not produce an allocation.'
        );
    }

    /**
     * @description Verifies negative budgets are rejected.
     */
    @IsTest
    static void testNegativeBudget() {
        Id termId = UserInfo.getUserId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(termId, 100, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(-1000.00, lines);
        Test.stopTest();

        System.assertEquals(
            null,
            amounts.get(termId),
            'Negative budget must prevent allocation.'
        );
    }

    /**
     * @description Ensures missing percentage values
     * prevent payment allocation.
     */
    @IsTest
    static void testNullPercentage() {
        Id termId = UserInfo.getUserId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(termId, null, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            null,
            amounts.get(termId),
            'Missing percentage must prevent allocation.'
        );
    }

    /**
     * @description Verifies negative allocation
     * percentages are rejected.
     */
    @IsTest
    static void testNegativePercentage() {
        Id termId = UserInfo.getUserId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(termId, -25, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            null,
            amounts.get(termId),
            'Negative percentage must prevent allocation.'
        );
    }

    /**
     * @description Verifies zero total allocation
     * weight does not trigger division.
     */
    @IsTest
    static void testZeroTotalWeight() {
        Id termId = UserInfo.getUserId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(termId, 0, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            null,
            amounts.get(termId),
            'Zero total weight must prevent allocation.'
        );
    }

    /**
     * @description Ensures already-paid terms
     * preserve their recorded values.
     */
    @IsTest
    static void testAllTermsPaid() {
        Id firstId = UserInfo.getUserId();
        Id secondId = UserInfo.getOrganizationId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(firstId, 50, true, 45000.00),
                createLine(secondId, 50, true, 55000.00)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            45000.00,
            amounts.get(firstId),
            'First historical payment must be retained.'
        );
        System.assertEquals(
            55000.00,
            amounts.get(secondId),
            'Second historical payment must be retained.'
        );
    }

    /**
     * @description Validates handling of an empty
     * payment schedule.
     */
    @IsTest
    static void testEmptyPaymentSchedule() {
        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>();

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            true,
            amounts.isEmpty(),
            'Empty input must return an empty allocation map.'
        );
    }

    /**
     * @description Validates cumulative rounding
     * and preservation of the final paise.
     */
    @IsTest
    static void testCumulativeRounding() {
        Id firstId = UserInfo.getUserId();
        Id secondId = UserInfo.getOrganizationId();
        Id thirdId = UserInfo.getProfileId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(firstId, 1, false, null),
                createLine(secondId, 1, false, null),
                createLine(thirdId, 1, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(100.00, lines);
        Test.stopTest();

        Decimal total =
            amounts.get(firstId)
            + amounts.get(secondId)
            + amounts.get(thirdId);

        System.assertEquals(
            33.33,
            amounts.get(firstId),
            'First term must be rounded correctly.'
        );
        System.assertEquals(
            33.34,
            amounts.get(secondId),
            'Second term must receive cumulative rounding.'
        );
        System.assertEquals(
            33.33,
            amounts.get(thirdId),
            'Final term must receive the remaining amount.'
        );
        System.assertEquals(
            100.00,
            total,
            'Allocated amounts must equal the full balance.'
        );
    }

    /**
     * @description Verifies historical payment rounding
     * before calculating the remaining balance.
     */
    @IsTest
    static void testHistoricalPaymentRounding() {
        Id paidId = UserInfo.getUserId();
        Id unpaidId = UserInfo.getOrganizationId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(paidId, 25, true, 100.126),
                createLine(unpaidId, 75, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(1000.00, lines);
        Test.stopTest();

        System.assertEquals(
            100.13,
            amounts.get(paidId),
            'Historical payment must be rounded to two decimals.'
        );
        System.assertEquals(
            899.87,
            amounts.get(unpaidId),
            'Balance must use the rounded historical payment.'
        );
    }

    /**
     * @description Ensures a zero budget produces
     * zero allocations for unpaid terms.
     */
    @IsTest
    static void testZeroBudget() {
        Id termId = UserInfo.getUserId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(termId, 100, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(ZERO_AMOUNT, lines);
        Test.stopTest();

        System.assertEquals(
            ZERO_AMOUNT,
            amounts.get(termId),
            'Zero budget must produce zero allocation.'
        );
    }

    /**
     * @description Ensures zero-weight unpaid terms
     * receive no allocation when other weights exist.
     */
    @IsTest
    static void testZeroWeightWithPositiveWeight() {
        Id firstId = UserInfo.getUserId();
        Id secondId = UserInfo.getOrganizationId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(firstId, 0, false, null),
                createLine(secondId, 100, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            ZERO_AMOUNT,
            amounts.get(firstId),
            'Zero-weight term must receive zero allocation.'
        );
        System.assertEquals(
            BUDGET,
            amounts.get(secondId),
            'Positive-weight term must receive the entire balance.'
        );
    }

    /**
     * @description Verifies unpaid allocations use
     * relative weights rather than requiring 100%.
     */
    @IsTest
    static void testRelativeWeightAllocation() {
        Id firstId = UserInfo.getUserId();
        Id secondId = UserInfo.getOrganizationId();

        List<PaymentScheduleCalculator.Line> lines =
            new List<PaymentScheduleCalculator.Line>{
                createLine(firstId, 20, false, null),
                createLine(secondId, 30, false, null)
            };

        Test.startTest();
        Map<Id, Decimal> amounts =
            PaymentScheduleCalculator.allocate(BUDGET, lines);
        Test.stopTest();

        System.assertEquals(
            40000.00,
            amounts.get(firstId),
            'Relative weight 20/50 must receive 40%.'
        );
        System.assertEquals(
            60000.00,
            amounts.get(secondId),
            'Relative weight 30/50 must receive 60%.'
        );
    }
}
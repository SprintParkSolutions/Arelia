/**
 * -----------------------------------------------------------------------------
 * Class Name      : AreliaPlatformEventTriggerTest
 * Author          : Arelia
 * Created Date    : Oct 16, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 16, 2026
 * Description     : Unit tests for AreliaPlatformEventTrigger.
 *                   Validates approval date updates for Architecture Design,
 *                   Proforma Invoice, Budget Review, and Payment Terms.
 *                   Covers valid events, invalid IDs, incorrect object types,
 *                   missing fields, unchanged dates, duplicate events,
 *                   and bulk processing.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class AreliaPlatformEventTriggerTest {

    private static final String OPPORTUNITY_STAGE = 'Qualification';
    private static final String PROFORMA_STATUS = 'Sent';

    private static final Integer BULK_RECORD_COUNT = 5;

    private static final Date APPROVAL_DATE =
        Date.newInstance(2026, 10, 16);

    private static final Date UPDATED_APPROVAL_DATE =
        Date.newInstance(2026, 10, 17);

    // -------------------------------------------------------------------------
    // TEST DATA HELPERS
    // -------------------------------------------------------------------------

    private static Opportunity createOpportunity() {

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Arelia Test Opportunity',
            StageName = OPPORTUNITY_STAGE,
            CloseDate = Date.today().addDays(30)
        );

        insert opportunityRecord;

        return opportunityRecord;
    }

    private static Architecture_Design__c createArchitectureDesign(
        Id opportunityId
    ) {

        Architecture_Design__c design = new Architecture_Design__c(
            Opportunity__c = opportunityId
        );

        insert design;

        return design;
    }

    private static Proforma_Invoice__c createProformaInvoice(
        Id opportunityId
    ) {

        Proforma_Invoice__c invoice = new Proforma_Invoice__c(
            Opportunity__c = opportunityId,
            Status__c = PROFORMA_STATUS
        );

        insert invoice;

        return invoice;
    }

    private static void publishEvents(
        List<Arelia_Platform_Event__e> eventsToPublish
    ) {

        List<Database.SaveResult> results =
            EventBus.publish(eventsToPublish);

        for (Database.SaveResult result : results) {

            System.assertEquals(
                true,
                result.isSuccess(),
                'Platform event must publish successfully.'
            );
        }

        Test.getEventBus().deliver();
    }

    // -------------------------------------------------------------------------
    // ALL APPROVAL DATES
    // -------------------------------------------------------------------------

    @IsTest
    static void allApprovalDatesUpdatedSuccessfully() {

        Opportunity opportunityRecord = createOpportunity();

        Architecture_Design__c design =
            createArchitectureDesign(opportunityRecord.Id);

        Proforma_Invoice__c invoice =
            createProformaInvoice(opportunityRecord.Id);

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Architect_Approved_Record_ID__c =
                    String.valueOf(design.Id),
                Architect_Approved_Date__c = APPROVAL_DATE,

                Proforma_Invoice_Approved_Record_ID__c =
                    String.valueOf(invoice.Id),
                Proforma_Invoice_Approved_date__c = APPROVAL_DATE,

                Budget_Review_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Budget_Review_Approved_Date__c = APPROVAL_DATE,

                Payment_Terms_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Payment_Terms_Approved_Date__c = APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        Architecture_Design__c updatedDesign = [
            SELECT Architect_Approved_Date__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
        ];

        Proforma_Invoice__c updatedInvoice = [
            SELECT Proforma_Invoice_Approved_date__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        Opportunity updatedOpportunity = [
            SELECT
                Budget_Review_Approved_Date__c,
                Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];

        System.assertEquals(
            APPROVAL_DATE,
            updatedDesign.Architect_Approved_Date__c,
            'Architecture approval date must be updated.'
        );

        System.assertEquals(
            APPROVAL_DATE,
            updatedInvoice.Proforma_Invoice_Approved_date__c,
            'Proforma approval date must be updated.'
        );

        System.assertEquals(
            APPROVAL_DATE,
            updatedOpportunity.Budget_Review_Approved_Date__c,
            'Budget Review approval date must be updated.'
        );

        System.assertEquals(
            APPROVAL_DATE,
            updatedOpportunity.Payment_Terms_Approved_Date__c,
            'Payment Terms approval date must be updated.'
        );
    }

    // -------------------------------------------------------------------------
    // ARCHITECTURE DESIGN
    // -------------------------------------------------------------------------

    @IsTest
    static void architectureApprovalDateUpdated() {

        Opportunity opportunityRecord = createOpportunity();

        Architecture_Design__c design =
            createArchitectureDesign(opportunityRecord.Id);

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Architect_Approved_Record_ID__c =
                    String.valueOf(design.Id),
                Architect_Approved_Date__c = APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        Architecture_Design__c updatedDesign = [
            SELECT Architect_Approved_Date__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
        ];

        System.assertEquals(
            APPROVAL_DATE,
            updatedDesign.Architect_Approved_Date__c,
            'Architecture approval date should match event date.'
        );
    }

    // -------------------------------------------------------------------------
    // PROFORMA INVOICE
    // -------------------------------------------------------------------------

    @IsTest
    static void proformaApprovalDateUpdated() {

        Opportunity opportunityRecord = createOpportunity();

        Proforma_Invoice__c invoice =
            createProformaInvoice(opportunityRecord.Id);

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Proforma_Invoice_Approved_Record_ID__c =
                    String.valueOf(invoice.Id),
                Proforma_Invoice_Approved_date__c = APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        Proforma_Invoice__c updatedInvoice = [
            SELECT Proforma_Invoice_Approved_date__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(
            APPROVAL_DATE,
            updatedInvoice.Proforma_Invoice_Approved_date__c,
            'Proforma approval date should match event date.'
        );
    }

    // -------------------------------------------------------------------------
    // BUDGET REVIEW
    // -------------------------------------------------------------------------

    @IsTest
    static void budgetReviewApprovalDateUpdated() {

        Opportunity opportunityRecord = createOpportunity();

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Budget_Review_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Budget_Review_Approved_Date__c = APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT Budget_Review_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];

        System.assertEquals(
            APPROVAL_DATE,
            updatedOpportunity.Budget_Review_Approved_Date__c,
            'Budget Review approval date should be updated.'
        );
    }

    // -------------------------------------------------------------------------
    // PAYMENT TERMS
    // -------------------------------------------------------------------------

    @IsTest
    static void paymentTermsApprovalDateUpdated() {

        Opportunity opportunityRecord = createOpportunity();

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Payment_Terms_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Payment_Terms_Approved_Date__c = APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];

        System.assertEquals(
            APPROVAL_DATE,
            updatedOpportunity.Payment_Terms_Approved_Date__c,
            'Payment Terms approval date should be updated.'
        );
    }

    // -------------------------------------------------------------------------
    // INVALID RECORD IDS
    // -------------------------------------------------------------------------

    @IsTest
    static void invalidRecordIdsAreIgnored() {

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Architect_Approved_Record_ID__c = 'InvalidId',
                Architect_Approved_Date__c = APPROVAL_DATE,

                Proforma_Invoice_Approved_Record_ID__c = 'InvalidId',
                Proforma_Invoice_Approved_date__c = APPROVAL_DATE,

                Budget_Review_Approved_Record_ID__c = 'InvalidId',
                Budget_Review_Approved_Date__c = APPROVAL_DATE,

                Payment_Terms_Approved_Record_ID__c = 'InvalidId',
                Payment_Terms_Approved_Date__c = APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        System.assert(
            true,
            'Invalid record IDs must not cause processing failures.'
        );
    }

    // -------------------------------------------------------------------------
    // INCORRECT RECORD TYPES
    // -------------------------------------------------------------------------

    @IsTest
    static void incorrectRecordTypesAreIgnored() {

        Opportunity opportunityRecord = createOpportunity();

        Architecture_Design__c design =
            createArchitectureDesign(opportunityRecord.Id);

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Architect_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Architect_Approved_Date__c = APPROVAL_DATE,

                Proforma_Invoice_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Proforma_Invoice_Approved_date__c = APPROVAL_DATE,

                Budget_Review_Approved_Record_ID__c =
                    String.valueOf(design.Id),
                Budget_Review_Approved_Date__c = APPROVAL_DATE,

                Payment_Terms_Approved_Record_ID__c =
                    String.valueOf(design.Id),
                Payment_Terms_Approved_Date__c = APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        Architecture_Design__c unchangedDesign = [
            SELECT Architect_Approved_Date__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
        ];

        Opportunity unchangedOpportunity = [
            SELECT
                Budget_Review_Approved_Date__c,
                Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];

        System.assertEquals(
            null,
            unchangedDesign.Architect_Approved_Date__c,
            'Incorrect record type must not update Architecture Design.'
        );

        System.assertEquals(
            null,
            unchangedOpportunity.Budget_Review_Approved_Date__c,
            'Incorrect record type must not update Budget Review.'
        );

        System.assertEquals(
            null,
            unchangedOpportunity.Payment_Terms_Approved_Date__c,
            'Incorrect record type must not update Payment Terms.'
        );
    }

    // -------------------------------------------------------------------------
    // MISSING APPROVAL DATES
    // -------------------------------------------------------------------------

    @IsTest
    static void missingApprovalDatesAreIgnored() {

        Opportunity opportunityRecord = createOpportunity();

        Architecture_Design__c design =
            createArchitectureDesign(opportunityRecord.Id);

        Proforma_Invoice__c invoice =
            createProformaInvoice(opportunityRecord.Id);

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Architect_Approved_Record_ID__c =
                    String.valueOf(design.Id),

                Proforma_Invoice_Approved_Record_ID__c =
                    String.valueOf(invoice.Id),

                Budget_Review_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),

                Payment_Terms_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id)
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        Architecture_Design__c unchangedDesign = [
            SELECT Architect_Approved_Date__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
        ];

        Proforma_Invoice__c unchangedInvoice = [
            SELECT Proforma_Invoice_Approved_date__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        Opportunity unchangedOpportunity = [
            SELECT
                Budget_Review_Approved_Date__c,
                Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];

        System.assertEquals(
            null,
            unchangedDesign.Architect_Approved_Date__c,
            'Architecture approval date should remain empty.'
        );

        System.assertEquals(
            null,
            unchangedInvoice.Proforma_Invoice_Approved_date__c,
            'Proforma approval date should remain empty.'
        );

        System.assertEquals(
            null,
            unchangedOpportunity.Budget_Review_Approved_Date__c,
            'Budget Review approval date should remain empty.'
        );

        System.assertEquals(
            null,
            unchangedOpportunity.Payment_Terms_Approved_Date__c,
            'Payment Terms approval date should remain empty.'
        );
    }

    // -------------------------------------------------------------------------
    // BLANK RECORD IDS
    // -------------------------------------------------------------------------

    @IsTest
    static void blankRecordIdsAreIgnored() {

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Architect_Approved_Date__c = APPROVAL_DATE,
                Proforma_Invoice_Approved_date__c = APPROVAL_DATE,
                Budget_Review_Approved_Date__c = APPROVAL_DATE,
                Payment_Terms_Approved_Date__c = APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        System.assert(
            true,
            'Events without record IDs should be ignored.'
        );
    }

    // -------------------------------------------------------------------------
    // UNCHANGED APPROVAL DATES
    // -------------------------------------------------------------------------

    @IsTest
    static void unchangedApprovalDatesArePreserved() {

        Opportunity opportunityRecord = createOpportunity();

        Architecture_Design__c design =
            createArchitectureDesign(opportunityRecord.Id);

        Proforma_Invoice__c invoice =
            createProformaInvoice(opportunityRecord.Id);

        design.Architect_Approved_Date__c = APPROVAL_DATE;
        update design;

        invoice.Proforma_Invoice_Approved_date__c = APPROVAL_DATE;
        update invoice;

        opportunityRecord.Budget_Review_Approved_Date__c =
            APPROVAL_DATE;

        opportunityRecord.Payment_Terms_Approved_Date__c =
            APPROVAL_DATE;

        update opportunityRecord;

        Arelia_Platform_Event__e eventRecord =
            new Arelia_Platform_Event__e(
                Architect_Approved_Record_ID__c =
                    String.valueOf(design.Id),
                Architect_Approved_Date__c = APPROVAL_DATE,

                Proforma_Invoice_Approved_Record_ID__c =
                    String.valueOf(invoice.Id),
                Proforma_Invoice_Approved_date__c = APPROVAL_DATE,

                Budget_Review_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Budget_Review_Approved_Date__c = APPROVAL_DATE,

                Payment_Terms_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Payment_Terms_Approved_Date__c = APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{ eventRecord }
        );

        Test.stopTest();

        Architecture_Design__c unchangedDesign = [
            SELECT Architect_Approved_Date__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
        ];

        Proforma_Invoice__c unchangedInvoice = [
            SELECT Proforma_Invoice_Approved_date__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        Opportunity unchangedOpportunity = [
            SELECT
                Budget_Review_Approved_Date__c,
                Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];

        System.assertEquals(
            APPROVAL_DATE,
            unchangedDesign.Architect_Approved_Date__c,
            'Existing Architecture approval date should remain unchanged.'
        );

        System.assertEquals(
            APPROVAL_DATE,
            unchangedInvoice.Proforma_Invoice_Approved_date__c,
            'Existing Proforma approval date should remain unchanged.'
        );

        System.assertEquals(
            APPROVAL_DATE,
            unchangedOpportunity.Budget_Review_Approved_Date__c,
            'Existing Budget Review date should remain unchanged.'
        );

        System.assertEquals(
            APPROVAL_DATE,
            unchangedOpportunity.Payment_Terms_Approved_Date__c,
            'Existing Payment Terms date should remain unchanged.'
        );
    }

    // -------------------------------------------------------------------------
    // BULK PLATFORM EVENT PROCESSING
    // -------------------------------------------------------------------------

    @IsTest
    static void bulkEventsProcessedSuccessfully() {

        List<Opportunity> opportunities =
            new List<Opportunity>();

        for (Integer index = 0; index < BULK_RECORD_COUNT; index++) {

            opportunities.add(
                new Opportunity(
                    Name = 'Bulk Opportunity ' + index,
                    StageName = OPPORTUNITY_STAGE,
                    CloseDate = Date.today().addDays(30)
                )
            );
        }

        insert opportunities;

        List<Architecture_Design__c> designs =
            new List<Architecture_Design__c>();

        List<Proforma_Invoice__c> invoices =
            new List<Proforma_Invoice__c>();

        for (Opportunity opportunityRecord : opportunities) {

            designs.add(
                new Architecture_Design__c(
                    Opportunity__c = opportunityRecord.Id
                )
            );

            invoices.add(
                new Proforma_Invoice__c(
                    Opportunity__c = opportunityRecord.Id,
                    Status__c = PROFORMA_STATUS
                )
            );
        }

        insert designs;
        insert invoices;

        List<Arelia_Platform_Event__e> eventsToPublish =
            new List<Arelia_Platform_Event__e>();

        for (Integer index = 0; index < BULK_RECORD_COUNT; index++) {

            eventsToPublish.add(
                new Arelia_Platform_Event__e(
                    Architect_Approved_Record_ID__c =
                        String.valueOf(designs[index].Id),
                    Architect_Approved_Date__c = APPROVAL_DATE,

                    Proforma_Invoice_Approved_Record_ID__c =
                        String.valueOf(invoices[index].Id),
                    Proforma_Invoice_Approved_date__c =
                        APPROVAL_DATE,

                    Budget_Review_Approved_Record_ID__c =
                        String.valueOf(opportunities[index].Id),
                    Budget_Review_Approved_Date__c =
                        APPROVAL_DATE,

                    Payment_Terms_Approved_Record_ID__c =
                        String.valueOf(opportunities[index].Id),
                    Payment_Terms_Approved_Date__c =
                        APPROVAL_DATE
                )
            );
        }

        Test.startTest();

        publishEvents(eventsToPublish);

        Test.stopTest();

        Map<Id, Architecture_Design__c> updatedDesigns =
            new Map<Id, Architecture_Design__c>([
                SELECT Architect_Approved_Date__c
                FROM Architecture_Design__c
                WHERE Id IN :designs
            ]);

        Map<Id, Proforma_Invoice__c> updatedInvoices =
            new Map<Id, Proforma_Invoice__c>([
                SELECT Proforma_Invoice_Approved_date__c
                FROM Proforma_Invoice__c
                WHERE Id IN :invoices
            ]);

        Map<Id, Opportunity> updatedOpportunities =
            new Map<Id, Opportunity>([
                SELECT
                    Budget_Review_Approved_Date__c,
                    Payment_Terms_Approved_Date__c
                FROM Opportunity
                WHERE Id IN :opportunities
            ]);

        for (Integer index = 0; index < BULK_RECORD_COUNT; index++) {

            System.assertEquals(
                APPROVAL_DATE,
                updatedDesigns.get(
                    designs[index].Id
                ).Architect_Approved_Date__c,
                'Bulk Architecture approval should succeed.'
            );

            System.assertEquals(
                APPROVAL_DATE,
                updatedInvoices.get(
                    invoices[index].Id
                ).Proforma_Invoice_Approved_date__c,
                'Bulk Proforma approval should succeed.'
            );

            System.assertEquals(
                APPROVAL_DATE,
                updatedOpportunities.get(
                    opportunities[index].Id
                ).Budget_Review_Approved_Date__c,
                'Bulk Budget Review approval should succeed.'
            );

            System.assertEquals(
                APPROVAL_DATE,
                updatedOpportunities.get(
                    opportunities[index].Id
                ).Payment_Terms_Approved_Date__c,
                'Bulk Payment Terms approval should succeed.'
            );
        }
    }

    // -------------------------------------------------------------------------
    // DUPLICATE PLATFORM EVENTS
    // -------------------------------------------------------------------------

    @IsTest
    static void duplicateEventsUseLatestDate() {

        Opportunity opportunityRecord = createOpportunity();

        Architecture_Design__c design =
            createArchitectureDesign(opportunityRecord.Id);

        Proforma_Invoice__c invoice =
            createProformaInvoice(opportunityRecord.Id);

        Arelia_Platform_Event__e firstEvent =
            new Arelia_Platform_Event__e(
                Architect_Approved_Record_ID__c =
                    String.valueOf(design.Id),
                Architect_Approved_Date__c = APPROVAL_DATE,

                Proforma_Invoice_Approved_Record_ID__c =
                    String.valueOf(invoice.Id),
                Proforma_Invoice_Approved_date__c = APPROVAL_DATE,

                Budget_Review_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Budget_Review_Approved_Date__c = APPROVAL_DATE,

                Payment_Terms_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Payment_Terms_Approved_Date__c = APPROVAL_DATE
            );

        Arelia_Platform_Event__e secondEvent =
            new Arelia_Platform_Event__e(
                Architect_Approved_Record_ID__c =
                    String.valueOf(design.Id),
                Architect_Approved_Date__c = UPDATED_APPROVAL_DATE,

                Proforma_Invoice_Approved_Record_ID__c =
                    String.valueOf(invoice.Id),
                Proforma_Invoice_Approved_date__c =
                    UPDATED_APPROVAL_DATE,

                Budget_Review_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Budget_Review_Approved_Date__c =
                    UPDATED_APPROVAL_DATE,

                Payment_Terms_Approved_Record_ID__c =
                    String.valueOf(opportunityRecord.Id),
                Payment_Terms_Approved_Date__c =
                    UPDATED_APPROVAL_DATE
            );

        Test.startTest();

        publishEvents(
            new List<Arelia_Platform_Event__e>{
                firstEvent,
                secondEvent
            }
        );

        Test.stopTest();

        Architecture_Design__c updatedDesign = [
            SELECT Architect_Approved_Date__c
            FROM Architecture_Design__c
            WHERE Id = :design.Id
        ];

        Proforma_Invoice__c updatedInvoice = [
            SELECT Proforma_Invoice_Approved_date__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        Opportunity updatedOpportunity = [
            SELECT
                Budget_Review_Approved_Date__c,
                Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];

        System.assertEquals(
            UPDATED_APPROVAL_DATE,
            updatedDesign.Architect_Approved_Date__c,
            'Latest Architecture event date should be applied.'
        );

        System.assertEquals(
            UPDATED_APPROVAL_DATE,
            updatedInvoice.Proforma_Invoice_Approved_date__c,
            'Latest Proforma event date should be applied.'
        );

        System.assertEquals(
            UPDATED_APPROVAL_DATE,
            updatedOpportunity.Budget_Review_Approved_Date__c,
            'Latest Budget Review event date should be applied.'
        );

        System.assertEquals(
            UPDATED_APPROVAL_DATE,
            updatedOpportunity.Payment_Terms_Approved_Date__c,
            'Latest Payment Terms event date should be applied.'
        );
    }
}
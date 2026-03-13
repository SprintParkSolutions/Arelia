@IsTest
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveAsserts')
public class InvoiceServiceTest {

    // =========================================================
    // Helpers
    // =========================================================

    private static InvoiceService.PayloadDTO buildPayload(Id oppId, Id existingInvoiceId) {
        InvoiceService.PayloadDTO p = new InvoiceService.PayloadDTO();
        p.opportunityId = oppId;
        p.existingInvoiceId = existingInvoiceId;

        p.header = new InvoiceService.HeaderDTO();
        p.header.clientName = 'Client A';
        p.header.phone = '9999999999';
        p.header.clientAddress = 'Address 123';
        p.header.invoiceDate = Date.today();
        p.header.invoiceNo = 'INV-001';
        p.header.gstPercent = 18;

        p.sections = new List<InvoiceService.SectionDTO>();

        // WOOD
        InvoiceService.SectionDTO wood = new InvoiceService.SectionDTO();
        wood.sectionName = 'Wood Work';
        wood.sectionType = 'WOOD';
        wood.lines = new List<InvoiceService.LineDTO>();

        InvoiceService.LineDTO w1 = new InvoiceService.LineDTO();
        w1.category = 'Cat-W';
        w1.item = 'Item-W1';
        w1.brand = 'Brand-W';
        w1.explanation = 'Explain-W';
        w1.l = 12;
        w1.h = 24;
        w1.qty = 2;
        w1.rate = 50;
        wood.lines.add(w1);
        p.sections.add(wood);

        // ELECTRICAL
        InvoiceService.SectionDTO elec = new InvoiceService.SectionDTO();
        elec.sectionName = 'Electrical';
        elec.sectionType = 'ELECTRICAL';
        elec.lines = new List<InvoiceService.LineDTO>();

        InvoiceService.LineDTO e1 = new InvoiceService.LineDTO();
        e1.category = 'Cat-E';
        e1.item = 'Item-E1';
        e1.electricalMode = 'COILS';
        e1.coils = 1;
        e1.meters = 30;
        e1.rate = 10;
        elec.lines.add(e1);

        InvoiceService.LineDTO e2 = new InvoiceService.LineDTO();
        e2.category = 'Cat-E';
        e2.item = 'Item-E2';
        e2.electricalMode = 'QTY';
        e2.qty = 5;
        e2.rate = 20;
        elec.lines.add(e2);

        p.sections.add(elec);

        // OTHER (restricted picklist value must match exactly)
        InvoiceService.SectionDTO oth = new InvoiceService.SectionDTO();
        oth.sectionName = 'Other Works';
        oth.sectionType = 'Other Works';
        oth.lines = new List<InvoiceService.LineDTO>();

        InvoiceService.LineDTO o1 = new InvoiceService.LineDTO();
        o1.category = 'Cat-O';
        o1.item = '3D Designing Charges';
        o1.amount = 30000;
        oth.lines.add(o1);

        p.sections.add(oth);

        // Materials
        p.materials = new List<InvoiceService.MaterialDTO>();
        InvoiceService.MaterialDTO m = new InvoiceService.MaterialDTO();
        m.material = 'PLY';
        m.brand = 'Greenply';
        m.grade = 'BWP';
        m.sortOrder = 1;
        p.materials.add(m);

        // Not included
        p.notIncluded = new List<InvoiceService.NotIncludedDTO>();
        InvoiceService.NotIncludedDTO n = new InvoiceService.NotIncludedDTO();
        n.text = 'Painting not included';
        n.sortOrder = 1;
        p.notIncluded.add(n);

        // Totals
        p.total = 0;
        p.gstAmount = 0;
        p.grandTotal = 99999;

        return p;
    }

    private static String toJson(InvoiceService.PayloadDTO p) {
        return JSON.serialize(p);
    }

    /**
     * Alias on User has max length = 8.
     * This helper guarantees safe alias for TestDataUtility.createSupervisorUser().
     */
    private static String safeAlias(String raw) {
        String a = String.isBlank(raw) ? 'sup' : raw.trim();
        if (a.length() > 8) {
            a = a.substring(0, 8);
        }
        return a;
    }

    private static Opportunity setupOppWithSupervisor(String alias) {
        String a = safeAlias(alias);
        User sup = TestDataUtility.createSupervisorUser(a);
        return TestDataUtility.createOpportunity('Opp-' + a, sup.Id);
    }

    private static Invoice__c insertSubmittedInvoice(Id oppId, Integer versionNo) {
        Invoice__c inv = new Invoice__c(
            Opportunity__c = oppId,
            Status__c = 'Submitted',
            Version_No__c = versionNo,
            Client_Name__c = 'Prev Client',
            Invoice_No__c = 'PREV',
            Invoice_Date__c = Date.today().addDays(-10),
            Grand_Total__c = 1000
        );
        insert inv;
        return inv;
    }

    /**
     * Creates Invoice + 1 section header + 1 item row + 1 material + 1 not included.
     * IMPORTANT: sectionTypePicklistValue must match restricted picklist EXACTLY.
     */
    private static Invoice__c createInvoiceWithLinesMaterials(Id oppId, String sectionTypePicklistValue) {
        Invoice__c inv = new Invoice__c(
            Opportunity__c = oppId,
            Status__c = 'Submitted',
            Version_No__c = 1,
            Client_Name__c = 'Client X',
            Invoice_No__c = 'INV-CTL',
            Invoice_Date__c = Date.today(),
            GST_Percent__c = 18,
            Total__c = 100,
            GST_Amount__c = 18,
            Grand_Total__c = 118
        );
        insert inv;

        List<Invoice_Line__c> lines = new List<Invoice_Line__c>();

        lines.add(new Invoice_Line__c(
            Invoice__c = inv.Id,
            Sort_Order__c = 1,
            Is_Section__c = true,
            Section_Name__c = 'Sec',
            Section_Type__c = sectionTypePicklistValue
        ));

        lines.add(new Invoice_Line__c(
            Invoice__c = inv.Id,
            Sort_Order__c = 2,
            Is_Section__c = false,
            Section_Name__c = 'Sec',
            Section_Type__c = sectionTypePicklistValue,
            Category__c = 'C',
            Item__c = 'I',
            Amount__c = 200
        ));

        insert lines;

        insert new Invoice_Material__c(
            Invoice__c = inv.Id,
            Sort_Order__c = 1,
            Material__c = 'PLY',
            Brand__c = 'B',
            Grade__c = 'G'
        );

        insert new Invoice_Not_Included__c(
            Invoice__c = inv.Id,
            Sort_Order__c = 1,
            Text__c = 'NI'
        );

        return inv;
    }

    // =========================================================
    // InvoiceService tests
    // =========================================================

    @IsTest
    static void testInitReturnsEmptyWhenOppNull() {
        Test.startTest();
        InvoiceService.InitDTO dto = InvoiceService.init(null);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'InitDTO must not be null when oppId is null.');
        System.assertEquals(null, dto.invoiceId, 'invoiceId must be null when oppId is null.');
    }

    @IsTest
    static void testSaveDraftJsonCreatesAndUpdatesSameDraftAndChildren() {
        Opportunity opp = setupOppWithSupervisor('sup1');

        InvoiceService.PayloadDTO p1 = buildPayload(opp.Id, null);

        Id draftId;
        Id sameId;

        Test.startTest();
        draftId = InvoiceService.saveDraftJson(toJson(p1));

        InvoiceService.PayloadDTO p2 = buildPayload(opp.Id, draftId);
        p2.header.invoiceNo = 'INV-UPDATED';
        sameId = InvoiceService.saveDraftJson(toJson(p2));
        Test.stopTest();

        System.assertNotEquals(null, draftId, 'Draft Id must be returned.');
        System.assertEquals(draftId, sameId, 'Second save must update the same draft.');

        Invoice__c inv = [SELECT Status__c, Invoice_No__c, Grand_Total__c FROM Invoice__c WHERE Id = :draftId];
        System.assertEquals('Draft', inv.Status__c, 'Invoice must remain Draft.');
        System.assertEquals('INV-UPDATED', inv.Invoice_No__c, 'Invoice_No__c must update.');
        System.assertEquals(99999, inv.Grand_Total__c, 'Grand_Total__c must map from payload.');
    }

    @IsTest
    static void testInitPrefersDraftOverSubmittedAndBuildsDTOs() {
        Opportunity opp = setupOppWithSupervisor('sup2');

        insertSubmittedInvoice(opp.Id, 91);
        Id draftId = InvoiceService.saveDraftJson(toJson(buildPayload(opp.Id, null)));

        Test.startTest();
        InvoiceService.InitDTO dto = InvoiceService.init(opp.Id);
        Test.stopTest();

        System.assertEquals(draftId, dto.invoiceId, 'Init must return Draft invoice when Draft exists.');
        System.assertEquals('Draft', dto.status, 'Init status must be Draft.');
        System.assertNotEquals(null, dto.header, 'Header must not be null.');
        System.assert(dto.sections != null && dto.sections.size() >= 1, 'Sections must be returned.');
        System.assert(dto.materials != null && dto.materials.size() == 1, 'Materials must be returned.');
        System.assert(dto.notIncluded != null && dto.notIncluded.size() == 1, 'NotIncluded must be returned.');
    }

    @IsTest
    static void testSubmitJsonFromDraftSetsVersionAndPrevious() {
        Opportunity opp = setupOppWithSupervisor('sup3');
        Invoice__c prev = insertSubmittedInvoice(opp.Id, 91);

        Id draftId = InvoiceService.saveDraftJson(toJson(buildPayload(opp.Id, null)));

        Test.startTest();
        Id submittedId = InvoiceService.submitJson(toJson(buildPayload(opp.Id, draftId)));
        Test.stopTest();

        Invoice__c nowInv = [SELECT Status__c, Version_No__c, Previous_Invoice__c FROM Invoice__c WHERE Id = :submittedId];
        System.assertEquals('Submitted', nowInv.Status__c, 'Draft must convert to Submitted.');
        System.assertEquals(92, nowInv.Version_No__c.intValue(), 'Version must increment to 92.');
        System.assertEquals(prev.Id, nowInv.Previous_Invoice__c, 'Previous invoice must be linked.');
    }

    @IsTest
    static void testSubmitJsonCreatesNewSubmittedWhenNoExistingInvoiceId() {
        Opportunity opp = setupOppWithSupervisor('sup4');
        insertSubmittedInvoice(opp.Id, 2);

        Test.startTest();
        Id newSubmittedId = InvoiceService.submitJson(toJson(buildPayload(opp.Id, null)));
        Test.stopTest();

        Invoice__c inv = [SELECT Status__c, Version_No__c, Previous_Invoice__c FROM Invoice__c WHERE Id = :newSubmittedId];
        System.assertEquals('Submitted', inv.Status__c, 'Submit must create Submitted invoice.');
        System.assertEquals(3, inv.Version_No__c.intValue(), 'Version must increment to 3.');
        System.assertNotEquals(null, inv.Previous_Invoice__c, 'Previous invoice must be populated.');
    }

    @IsTest
    static void testSubmitJsonReturnsIfAlreadySubmitted() {
        Opportunity opp = setupOppWithSupervisor('sup5');

        Invoice__c inv = new Invoice__c(
            Opportunity__c = opp.Id,
            Status__c = 'Submitted',
            Version_No__c = 5,
            Grand_Total__c = 500
        );
        insert inv;

        Test.startTest();
        Id returnedId = InvoiceService.submitJson(toJson(buildPayload(opp.Id, inv.Id)));
        Test.stopTest();

        System.assertEquals(inv.Id, returnedId, 'Already Submitted must return same Id.');
    }

    // =========================================================
    // InvoicePdfController tests (restricted picklist safe)
    // =========================================================

    @IsTest
    static void testPdfControllerLoadsWoodSection() {
        Opportunity opp = setupOppWithSupervisor('ctl1');
        Invoice__c inv = createInvoiceWithLinesMaterials(opp.Id, 'WOOD');

        Test.setCurrentPage(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', String.valueOf(inv.Id));

        InvoicePdfController ctl = new InvoicePdfController();

        System.assertEquals(null, ctl.errorMessage, 'Controller must not error for valid invoice.');
        System.assertNotEquals(null, ctl.inv, 'Invoice must be loaded.');
        System.assertEquals(inv.Id, ctl.inv.Id, 'Loaded invoice id must match.');
        System.assertNotEquals(null, ctl.sections, 'Sections must not be null.');
        System.assertEquals(1, ctl.sections.size(), 'Must build 1 section.');
        System.assertEquals(true, ctl.sections[0].getIsWood(), 'WOOD section must be wood.');
        System.assertEquals(false, ctl.sections[0].getIsElectrical(), 'WOOD section must not be electrical.');
        System.assertEquals(false, ctl.sections[0].getIsOther(), 'WOOD section must not be other.');
    }

    @IsTest
    static void testPdfControllerLoadsElectricalOtherCivilBranches() {
        Opportunity opp = setupOppWithSupervisor('ctl2');

        // ELECTRICAL
        Invoice__c invElec = createInvoiceWithLinesMaterials(opp.Id, 'ELECTRICAL');
        Test.setCurrentPage(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', String.valueOf(invElec.Id));
        InvoicePdfController ctlElec = new InvoicePdfController();
        System.assertEquals(null, ctlElec.errorMessage, 'Electrical invoice should load without error.');
        System.assertEquals(true, ctlElec.sections[0].getIsElectrical(), 'Electrical section must be electrical.');

        // Other Works
        Invoice__c invOther = createInvoiceWithLinesMaterials(opp.Id, 'Other Works');
        Test.setCurrentPage(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', String.valueOf(invOther.Id));
        InvoicePdfController ctlOther = new InvoicePdfController();
        System.assertEquals(null, ctlOther.errorMessage, 'Other invoice should load without error.');
        System.assertEquals(true, ctlOther.sections[0].getIsOther(), 'Other section must be other.');

        // CIVIL WORK -> canonType maps CIVIL to WOOD behavior in your controller
        Invoice__c invCivil = createInvoiceWithLinesMaterials(opp.Id, 'CIVIL WORK');
        Test.setCurrentPage(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', String.valueOf(invCivil.Id));
        InvoicePdfController ctlCivil = new InvoicePdfController();
        System.assertEquals(null, ctlCivil.errorMessage, 'Civil invoice should load without error.');
        System.assertEquals(true, ctlCivil.sections[0].getIsWood(), 'Civil section must behave like WOOD.');
    }

    @IsTest
    static void testPdfControllerHandlesMissingId() {
        Test.setCurrentPage(Page.InvoicePdf);

        InvoicePdfController ctl = new InvoicePdfController();
        System.assertNotEquals(null, ctl.errorMessage, 'Missing id must set errorMessage.');
        System.assertNotEquals(null, ctl.inv, 'Controller must initialize inv even on error.');
    }

    @IsTest
    static void testPdfControllerHandlesInvalidIdFormat() {
        Test.setCurrentPage(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', 'NOT_AN_ID');

        InvoicePdfController ctl = new InvoicePdfController();
        System.assertNotEquals(null, ctl.errorMessage, 'Invalid id format must set errorMessage.');
    }

    @IsTest
    static void testPdfControllerHandlesInvoiceNotFoundUsingDeletedRecordId() {
        Opportunity opp = setupOppWithSupervisor('ctl3');

        Invoice__c inv = createInvoiceWithLinesMaterials(opp.Id, 'WOOD');
        Id deletedId = inv.Id;
        delete inv;

        Test.setCurrentPage(Page.InvoicePdf);
        ApexPages.currentPage().getParameters().put('id', String.valueOf(deletedId));

        InvoicePdfController ctl = new InvoicePdfController();
        System.assertNotEquals(null, ctl.errorMessage, 'Deleted invoice id must result in not found error.');
    }

    // =========================================================
    // InvoicePdfJob tests
    // =========================================================

    @IsTest
    static void testPdfJobReturnsWhenInvoiceIdNull() {
        Test.startTest();
        System.enqueueJob(new InvoicePdfJob(null));
        Test.stopTest();
        System.assert(true, 'Queueable must safely return when invoiceId is null.');
    }

    @IsTest
    static void testPdfJobReturnsWhenInvoiceNotFound() {
        Opportunity opp = setupOppWithSupervisor('job1');
        Invoice__c inv = new Invoice__c(Opportunity__c = opp.Id, Status__c = 'Submitted', Grand_Total__c = 10);
        insert inv;
        Id deletedId = inv.Id;
        delete inv;

        Test.startTest();
        System.enqueueJob(new InvoicePdfJob(deletedId));
        Test.stopTest();
        System.assert(true, 'Queueable must safely return when invoice record does not exist.');
    }

    @IsTest
    static void testPdfJobSuccessCreatesFileAndLinksToInvoice() {
        Opportunity opp = setupOppWithSupervisor('job2');

        Invoice__c inv = new Invoice__c(
            Opportunity__c = opp.Id,
            Status__c = 'Submitted',
            Invoice_No__c = 'INV-JOB',
            Grand_Total__c = 123
        );
        insert inv;

        Test.startTest();
        System.enqueueJob(new InvoicePdfJob(inv.Id));
        Test.stopTest();

        Invoice__c invAfter = [SELECT PDF_ContentDocumentId__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertNotEquals(null, invAfter.PDF_ContentDocumentId__c, 'PDF_ContentDocumentId__c must be set after job.');

        Integer linkCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :inv.Id];
        System.assert(linkCount > 0, 'ContentDocumentLink must exist after job.');
    }

    @IsTest
    static void testPdfJobOppNameFallbackWhenNoOpportunity() {
        // No need to create supervisor/opportunity here at all.
        // Create invoice WITHOUT opportunity lookup to force fallback oppName = inv.Name
        Invoice__c inv = new Invoice__c(
            Status__c = 'Submitted',
            Invoice_No__c = 'INV-NO-OPP',
            Grand_Total__c = 10
        );
        insert inv;

        Test.startTest();
        System.enqueueJob(new InvoicePdfJob(inv.Id));
        Test.stopTest();

        Invoice__c afterInv = [SELECT PDF_ContentDocumentId__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertNotEquals(null, afterInv.PDF_ContentDocumentId__c, 'PDF must be generated even without opportunity.');
    }

    @IsTest
    static void testSanitizeFileNameBranches() {
        System.assertEquals('Invoice', InvoicePdfJob.sanitizeFileName(''), 'Blank input must return Invoice.');

        String cleaned = InvoicePdfJob.sanitizeFileName('Inv<>:"/\\|?*   Test');
        System.assertEquals(true, cleaned.contains('Inv'), 'Must keep base text.');
        System.assertEquals(false, cleaned.contains('<'), 'Must remove illegal chars.');
        System.assertEquals(false, cleaned.contains('>'), 'Must remove illegal chars.');

        String longName = 'A'.repeat(200);
        String cut = InvoicePdfJob.sanitizeFileName(longName);
        System.assertEquals(80, cut.length(), 'Must truncate to 80 chars.');
    }

    @IsTest
    static void testPdfJobCatchBranchSetsPdfError() {
        Opportunity opp = setupOppWithSupervisor('job3');

        Invoice__c inv = new Invoice__c(
            Opportunity__c = opp.Id,
            Status__c = 'Submitted',
            Invoice_No__c = 'INV-ERR',
            Grand_Total__c = 10
        );
        insert inv;

        // Force exception in test only (requires @TestVisible hook in InvoicePdfJob)
        InvoicePdfJob.forcePdfException = true;

        Test.startTest();
        System.enqueueJob(new InvoicePdfJob(inv.Id));
        Test.stopTest();

        InvoicePdfJob.forcePdfException = false;

        Invoice__c afterInv = [SELECT PDF_Error__c, PDF_ContentDocumentId__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertNotEquals(null, afterInv.PDF_Error__c, 'PDF_Error__c must be populated when PDF generation fails.');
        System.assertEquals(null, afterInv.PDF_ContentDocumentId__c, 'No PDF doc id should be set on failure.');
    }
}
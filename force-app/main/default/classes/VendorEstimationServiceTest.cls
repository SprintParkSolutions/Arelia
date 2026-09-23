@IsTest
private class VendorEstimationServiceTest {

    // =====================================================
    // MOCK OPENAI CALLOUT RESPONSE
    // =====================================================
    private class OpenAIMock implements HttpCalloutMock {

        private String scenario;

        OpenAIMock(String scenarioName) {
            this.scenario = scenarioName;
        }

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (scenario == 'INVALID_RESPONSE') {
                res.setBody('{"invalid":true}');
                return res;
            }

            if (scenario == 'EMPTY_CHOICES') {
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'choices' => new List<Object>()
                }));
                return res;
            }

            String content = '';

            if (scenario == 'OPPORTUNITY_ESTIMATE') {

                content =
                    '```json\n' +
                    '[' +
                        '{"category":"Furniture","percentage":50},' +
                        '{"category":"Lighting","percentage":50}' +
                    ']' +
                    '\n```';

            } else if (scenario == 'IMAGE_ESTIMATE') {

                content =
                    '```json\n' +
                    '{' +
                        '"totalBudget":1000000,' +
                        '"usableBudget":800000,' +
                        '"vendors":[' +
                            '{"category":"Furniture","percentage":60},' +
                            '{"category":"Lighting","percentage":40}' +
                        ']' +
                    '}' +
                    '\n```';

            } else if (scenario == 'TASK_ESTIMATE') {

                content =
                    '```json\n' +
                    '[' +
                        '{"task":"Material Purchase","percentage":40},' +
                        '{"task":"Installation","percentage":60}' +
                    ']' +
                    '\n```';

            } else if (scenario == 'PROFORMA_SUCCESS') {

                content =
                    '```json\n' +
                    '{' +
                        '"sections":[' +
                            '{' +
                                '"name":"Furniture",' +
                                '"subtotal":400000,' +
                                '"items":[' +
                                    '{"item":"Sofa Set","qty":2,"rate":100000,"amount":200000}' +
                                ']' +
                            '}' +
                        '],' +
                        '"total":400000,' +
                        '"gst":72000,' +
                        '"grandTotal":472000' +
                    '}' +
                    '\n```';

            } else if (scenario == 'IMAGE_PROFORMA_SUCCESS') {

                content =
                    '```json\n' +
                    '{' +
                        '"projectSummary":{' +
                            '"projectType":"Residential Interior",' +
                            '"style":"Modern Luxury",' +
                            '"totalAreaSqft":1200,' +
                            '"estimatedDuration":"45 days"' +
                        '},' +
                        '"sections":[' +
                            '{' +
                                '"room":"Living Room",' +
                                '"category":"Furniture",' +
                                '"subtotal":250000,' +
                                '"items":[' +
                                    '{' +
                                        '"item":"TV Unit",' +
                                        '"description":"Premium laminate TV panel",' +
                                        '"unit":"sqft",' +
                                        '"qty":1,' +
                                        '"areaSqft":120,' +
                                        '"materialCost":150000,' +
                                        '"laborCost":50000,' +
                                        '"gst":36000,' +
                                        '"amount":236000' +
                                    '}' +
                                ']' +
                            '}' +
                        '],' +
                        '"totalMaterialCost":150000,' +
                        '"totalLaborCost":50000,' +
                        '"totalGST":36000,' +
                        '"grandTotal":236000' +
                    '}' +
                    '\n```';

            } else if (scenario == 'NO_SECTIONS') {

                content =
                    '```json\n' +
                    '{' +
                        '"message":"No sections returned"' +
                    '}' +
                    '\n```';

            } else if (scenario == 'BAD_JSON') {

                content = 'this is not valid json';

            } else {

                content =
                    '```json\n' +
                    '[' +
                        '{"category":"Default","percentage":100}' +
                    ']' +
                    '\n```';
            }

            Map<String, Object> responseBody = new Map<String, Object>{
                'choices' => new List<Object>{
                    new Map<String, Object>{
                        'message' => new Map<String, Object>{
                            'content' => content
                        }
                    }
                }
            };

            res.setBody(JSON.serialize(responseBody));
            return res;
        }
    }

    // =====================================================
    // TEST DATA HELPERS
    // =====================================================
    private static Account createAccount() {

        Account acc = new Account();
        acc.Name = 'Test Account';

        insert acc;
        return acc;
    }

    private static Opportunity createTestOpportunity(Decimal budgetValue) {

        Account acc = createAccount();

        Opportunity opp = new Opportunity();
        opp.Name = 'Test Interior Project';
        opp.AccountId = acc.Id;
        opp.StageName = 'Prospecting';
        opp.CloseDate = Date.today().addDays(30);
        opp.Description = 'Premium 3BHK interior design project';
        opp.Supervisor_Estimated_Budget__c = budgetValue;

        insert opp;
        return opp;
    }

    private static Id createTestContentDocument() {

        ContentVersion cv = new ContentVersion();
        cv.Title = 'Test Design Image';
        cv.PathOnClient = 'test-design.png';
        cv.VersionData = Blob.valueOf('Fake image data for test coverage');

        insert cv;

        ContentVersion insertedCv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        return insertedCv.ContentDocumentId;
    }

    private static List<VendorEstimationService.VendorEstimate> buildVendorList() {

        List<VendorEstimationService.VendorEstimate> vendors =
            new List<VendorEstimationService.VendorEstimate>();

        VendorEstimationService.VendorEstimate furniture =
            new VendorEstimationService.VendorEstimate();

        furniture.category = 'Furniture';
        furniture.percentage = 60;
        furniture.totalBudget = 1000000;
        furniture.usableBudget = 800000;
        furniture.estimatedAmount = 480000;

        vendors.add(furniture);

        VendorEstimationService.VendorEstimate lighting =
            new VendorEstimationService.VendorEstimate();

        lighting.category = 'Lighting';
        lighting.percentage = 40;
        lighting.totalBudget = 1000000;
        lighting.usableBudget = 800000;
        lighting.estimatedAmount = 320000;

        vendors.add(lighting);

        return vendors;
    }

    private static List<Object> getSections(Map<String, Object> result) {

        return (List<Object>) JSON.deserializeUntyped(
            JSON.serialize(result.get('sections'))
        );
    }

    // =====================================================
    // TEST 1: OPPORTUNITY ESTIMATION SUCCESS
    // =====================================================
    @IsTest
    static void testEstimateVendorsFromOpportunitySuccess() {

        Opportunity opp = createTestOpportunity(1000000);

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('OPPORTUNITY_ESTIMATE'));

        Test.startTest();

        List<VendorEstimationService.VendorEstimate> results =
            VendorEstimationService.estimateVendorsFromOpportunity(opp.Id);

        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals('Furniture', results[0].category);
        System.assertEquals(Decimal.valueOf('50'), results[0].percentage);
        System.assertEquals(Decimal.valueOf('1000000'), results[0].totalBudget);
        System.assertEquals(Decimal.valueOf('800000'), results[0].usableBudget);
        System.assertEquals(Decimal.valueOf('400000'), results[0].estimatedAmount);
    }

    // =====================================================
    // TEST 2: OPPORTUNITY ESTIMATION FALLBACK
    // =====================================================
    @IsTest
    static void testEstimateVendorsFromOpportunityFallback() {

        Opportunity opp = createTestOpportunity(null);

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('INVALID_RESPONSE'));

        Test.startTest();

        List<VendorEstimationService.VendorEstimate> results =
            VendorEstimationService.estimateVendorsFromOpportunity(opp.Id);

        Test.stopTest();

        System.assertEquals(5, results.size());
        System.assertEquals('Furniture', results[0].category);
        System.assertEquals(Decimal.valueOf('0'), results[0].totalBudget);
        System.assertEquals(Decimal.valueOf('0'), results[0].usableBudget);
        System.assertEquals(Decimal.valueOf('0'), results[0].estimatedAmount);
    }

    // =====================================================
    // TEST 3: IMAGE ESTIMATION SUCCESS
    // =====================================================
    @IsTest
    static void testEstimateFromImagesSuccess() {

        Id contentDocId = createTestContentDocument();

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('IMAGE_ESTIMATE'));

        Test.startTest();

        List<VendorEstimationService.VendorEstimate> results =
            VendorEstimationService.estimateFromImages(
                new List<Id>{ contentDocId }
            );

        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals('Furniture', results[0].category);
        System.assertEquals(Decimal.valueOf('60'), results[0].percentage);
        System.assertEquals(Decimal.valueOf('1000000'), results[0].totalBudget);
        System.assertEquals(Decimal.valueOf('800000'), results[0].usableBudget);
        System.assertEquals(Decimal.valueOf('480000'), results[0].estimatedAmount);
    }

    // =====================================================
    // TEST 4: TASK ESTIMATION SUCCESS
    // =====================================================
    @IsTest
    static void testEstimateTasksForVendorSuccess() {

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('TASK_ESTIMATE'));

        Test.startTest();

        List<VendorEstimationService.VendorTaskEstimate> results =
            VendorEstimationService.estimateTasksForVendor('Furniture', 100000);

        Test.stopTest();

        System.assertEquals(2, results.size());

        System.assertEquals('Material Purchase', results[0].taskName);
        System.assertEquals(Decimal.valueOf('40'), results[0].percentage);
        System.assertEquals(Decimal.valueOf('40000'), results[0].estimatedAmount);

        System.assertEquals('Installation', results[1].taskName);
        System.assertEquals(Decimal.valueOf('60'), results[1].percentage);
        System.assertEquals(Decimal.valueOf('60000'), results[1].estimatedAmount);
    }

    // =====================================================
    // TEST 5: GENERATE PROFORMA SUCCESS
    // =====================================================
    @IsTest
    static void testGenerateProformaSuccess() {

        List<VendorEstimationService.VendorEstimate> vendors = buildVendorList();

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('PROFORMA_SUCCESS'));

        Test.startTest();

        Map<String, Object> result =
            VendorEstimationService.generateProforma(vendors);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('sections'));

        System.assertEquals(
            Decimal.valueOf('400000'),
            Decimal.valueOf(String.valueOf(result.get('total')))
        );

        System.assertEquals(
            Decimal.valueOf('72000'),
            Decimal.valueOf(String.valueOf(result.get('gst')))
        );

        System.assertEquals(
            Decimal.valueOf('472000'),
            Decimal.valueOf(String.valueOf(result.get('grandTotal')))
        );

        List<Object> sections = getSections(result);
        System.assertEquals(1, sections.size());
    }

    // =====================================================
    // TEST 6: GENERATE PROFORMA FALLBACK - EMPTY CHOICES
    // =====================================================
    @IsTest
    static void testGenerateProformaFallbackEmptyChoices() {

        List<VendorEstimationService.VendorEstimate> vendors = buildVendorList();

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('EMPTY_CHOICES'));

        Test.startTest();

        Map<String, Object> result =
            VendorEstimationService.generateProforma(vendors);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('sections'));

        System.assertEquals(
            Decimal.valueOf('800000'),
            Decimal.valueOf(String.valueOf(result.get('total')))
        );

        System.assertEquals(
            Decimal.valueOf('144000'),
            Decimal.valueOf(String.valueOf(result.get('gst')))
        );

        System.assertEquals(
            Decimal.valueOf('944000'),
            Decimal.valueOf(String.valueOf(result.get('grandTotal')))
        );

        List<Object> sections = getSections(result);
        System.assertEquals(2, sections.size());
    }

    // =====================================================
    // TEST 7: GENERATE PROFORMA FALLBACK - NO SECTIONS
    // =====================================================
    @IsTest
    static void testGenerateProformaFallbackNoSections() {

        List<VendorEstimationService.VendorEstimate> vendors = buildVendorList();

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('NO_SECTIONS'));

        Test.startTest();

        Map<String, Object> result =
            VendorEstimationService.generateProforma(vendors);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('sections'));

        List<Object> sections = getSections(result);
        System.assertEquals(2, sections.size());
    }

    // =====================================================
    // TEST 8: GENERATE PROFORMA FALLBACK - BAD JSON CATCH
    // =====================================================
    @IsTest
    static void testGenerateProformaFallbackBadJson() {

        List<VendorEstimationService.VendorEstimate> vendors = buildVendorList();

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('BAD_JSON'));

        Test.startTest();

        Map<String, Object> result =
            VendorEstimationService.generateProforma(vendors);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('sections'));

        List<Object> sections = getSections(result);
        System.assertEquals(2, sections.size());
    }

    // =====================================================
    // TEST 9: IMAGE PROFORMA SUCCESS
    // =====================================================
    @IsTest
    static void testGenerateProformaFromImagesSuccess() {

        Id contentDocId = createTestContentDocument();
        List<VendorEstimationService.VendorEstimate> vendors = buildVendorList();

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('IMAGE_PROFORMA_SUCCESS'));

        Test.startTest();

        Map<String, Object> result =
            VendorEstimationService.generateProformaFromImages(
                new List<Id>{ contentDocId },
                vendors
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('projectSummary'));
        System.assert(result.containsKey('sections'));

        System.assertEquals(
            Decimal.valueOf('236000'),
            Decimal.valueOf(String.valueOf(result.get('grandTotal')))
        );

        List<Object> sections = getSections(result);
        System.assertEquals(1, sections.size());
    }

    // =====================================================
    // TEST 10: IMAGE PROFORMA FALLBACK - EMPTY CHOICES
    // =====================================================
    @IsTest
    static void testGenerateProformaFromImagesFallbackEmptyChoices() {

        Id contentDocId = createTestContentDocument();
        List<VendorEstimationService.VendorEstimate> vendors = buildVendorList();

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('EMPTY_CHOICES'));

        Test.startTest();

        Map<String, Object> result =
            VendorEstimationService.generateProformaFromImages(
                new List<Id>{ contentDocId },
                vendors
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('sections'));

        System.assertEquals(
            Decimal.valueOf('800000'),
            Decimal.valueOf(String.valueOf(result.get('total')))
        );

        System.assertEquals(
            Decimal.valueOf('144000'),
            Decimal.valueOf(String.valueOf(result.get('gst')))
        );

        System.assertEquals(
            Decimal.valueOf('944000'),
            Decimal.valueOf(String.valueOf(result.get('grandTotal')))
        );

        List<Object> sections = getSections(result);
        System.assertEquals(2, sections.size());
    }

    // =====================================================
    // TEST 11: IMAGE PROFORMA FALLBACK - NO SECTIONS
    // =====================================================
    @IsTest
    static void testGenerateProformaFromImagesFallbackNoSections() {

        Id contentDocId = createTestContentDocument();
        List<VendorEstimationService.VendorEstimate> vendors = buildVendorList();

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('NO_SECTIONS'));

        Test.startTest();

        Map<String, Object> result =
            VendorEstimationService.generateProformaFromImages(
                new List<Id>{ contentDocId },
                vendors
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('sections'));

        List<Object> sections = getSections(result);
        System.assertEquals(2, sections.size());
    }

    // =====================================================
    // TEST 12: IMAGE PROFORMA FALLBACK - BAD JSON CATCH
    // =====================================================
    @IsTest
    static void testGenerateProformaFromImagesFallbackBadJson() {

        Id contentDocId = createTestContentDocument();
        List<VendorEstimationService.VendorEstimate> vendors = buildVendorList();

        Test.setMock(HttpCalloutMock.class, new OpenAIMock('BAD_JSON'));

        Test.startTest();

        Map<String, Object> result =
            VendorEstimationService.generateProformaFromImages(
                new List<Id>{ contentDocId },
                vendors
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('sections'));

        List<Object> sections = getSections(result);
        System.assertEquals(2, sections.size());
    }
}
@IsTest
private class QualityConfigControllerTest {

    @IsTest
    static void testGetQualityOptions() {
        Test.startTest();
        
        // Execute the method
        List<Quality_Config__mdt> results = QualityConfigController.getQualityOptions();
        
        Test.stopTest();

        // Custom Metadata is visible in tests by default. 
        // We assert that the query successfully executes and returns a List (not null).
        Assert.isNotNull(results, 'The getQualityOptions method should return a valid list instance, not null.');
        
        // If you know for a fact that your org has Quality Config records deployed, 
        // you can uncomment the line below to strictly enforce that records are found.
        // Assert.isTrue(results.size() > 0, 'Should return at least one Quality Config metadata record.');
    }
}
@isTest
private class CaseServiceTest {

    @isTest
    static void testMobileQueueAssignment() {
        Group mobileQueue = [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND Name = 'Mobile Support Queue' LIMIT 1];

        Case c = new Case(
            Subject = 'Mobile Issue',
            Status = 'New',
            Priority = 'Medium',
            Product__c = 'Mobile'
        );

        insert c;

        Case insertedCase = [SELECT Id, OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(mobileQueue.Id, insertedCase.OwnerId);
    }

    @isTest
    static void testHighPriorityEscalationQueueAssignment() {
        Group escalationQueue = [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND Name = 'Senior Escalation Queue' LIMIT 1];

        Case c = new Case(
            Subject = 'Urgent Laptop Issue',
            Status = 'New',
            Priority = 'High',
            Product__c = 'Laptop'
        );

        insert c;

        Case insertedCase = [SELECT Id, OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(escalationQueue.Id, insertedCase.OwnerId);
    }

    @isTest
    static void testMissingProductQueueFallsBackToDefaultOwner() {
        Group defaultQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Technical Support Queue' LIMIT 1];

        Case c = new Case(
            Subject = 'Television Issue',
            Status = 'New',
            Priority = 'Medium',
            Product__c = 'Television'
        );

        insert c;

        Case insertedCase = [SELECT Id, OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            defaultQueue.Id,
            insertedCase.OwnerId,
            'When product queue is unavailable, owner should fall back to the default queue.'
        );
    }

    @isTest
    static void testSubjectKeywordAssignsQueueWhenProductMissing() {
        Group mobileQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Mobile Support Queue' LIMIT 1];

        Case c = new Case(
            Subject = 'My mobile battery drains fast',
            Description = 'General issue reported by customer.',
            Status = 'New',
            Priority = 'Medium'
        );

        insert c;

        Case insertedCase = [SELECT Id, OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            mobileQueue.Id,
            insertedCase.OwnerId,
            'Without product, subject keywords should assign the matching queue.'
        );
    }

    @isTest
    static void testDescriptionUsedOnlyWhenSubjectHasNoMatch() {
        Group laptopQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Laptop Support Queue' LIMIT 1];

        Case c = new Case(
            Subject = 'Need assistance',
            Description = 'This laptop keyboard is not working properly.',
            Status = 'New',
            Priority = 'Medium'
        );

        insert c;

        Case insertedCase = [SELECT Id, OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            laptopQueue.Id,
            insertedCase.OwnerId,
            'Description should be checked only after subject has no keyword match.'
        );
    }

    @isTest
    static void testSubjectTakesPriorityOverDescription() {
        Group mobileQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Mobile Support Queue' LIMIT 1];

        Case c = new Case(
            Subject = 'Mobile screen flickering issue',
            Description = 'Also mentioning laptop overheating in the details.',
            Status = 'New',
            Priority = 'Medium'
        );

        insert c;

        Case insertedCase = [SELECT Id, OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            mobileQueue.Id,
            insertedCase.OwnerId,
            'When subject has a match, description should not override queue selection.'
        );
    }

    @isTest
    static void testProductAliasRoutingAcrossAllCategories() {
        Map<String, Id> queueIdsByName = new Map<String, Id>();
        for (Group g : [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Queue'
            AND Name IN (
                'Laptop Support Queue',
                'Television Support Queue',
                'Home Appliance Support Queue',
                'Warranty Support Queue',
                'Technical Support Queue'
            )
        ]) {
            queueIdsByName.put(g.Name, g.Id);
        }

        List<Case> caseList = new List<Case>{
            new Case(Product__c = 'Laptop', Priority = 'Medium'),
            new Case(Product__c = 'TV', Priority = 'Medium'),
            new Case(Product__c = 'Applicanes', Priority = 'Medium'),
            new Case(Product__c = 'Warranty', Priority = 'Medium')
        };

        CaseService.assignQueue(caseList);

        assertQueueOrFallback(caseList[0], 'Laptop Support Queue', queueIdsByName);
        assertQueueOrFallback(caseList[1], 'Television Support Queue', queueIdsByName);
        assertQueueOrFallback(caseList[2], 'Home Appliance Support Queue', queueIdsByName);
        assertQueueOrFallback(caseList[3], 'Warranty Support Queue', queueIdsByName);
    }

    private static void assertQueueOrFallback(Case c, String expectedQueueName, Map<String, Id> queueIdsByName) {
        if (queueIdsByName.containsKey(expectedQueueName)) {
            System.assertEquals(
                queueIdsByName.get(expectedQueueName),
                c.OwnerId,
                'Case should be assigned to ' + expectedQueueName + ' when that queue exists.'
            );
            return;
        }

        if (queueIdsByName.containsKey('Technical Support Queue')) {
            System.assertEquals(
                queueIdsByName.get('Technical Support Queue'),
                c.OwnerId,
                'Case should fall back to Technical Support Queue when the target queue is missing.'
            );
            return;
        }

        System.assertEquals(
            UserInfo.getUserId(),
            c.OwnerId,
            'Case should fall back to current user when no queue mapping is available.'
        );
    }
}
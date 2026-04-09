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
}
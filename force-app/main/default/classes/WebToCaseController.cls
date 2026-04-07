public with sharing class WebToCaseController {

    /**
     * Create a Support Case from Web-to-Case form submission
     * @param name - Customer name
     * @param email - Customer email
     * @param subject - Case subject
     * @param description - Detailed issue description
     * @param product - Product category
     * @param issueType - Type of issue
     * @return Case ID of the created case
     */
    @AuraEnabled
    public static Id createCase(String name, String email, String subject, 
                                 String description, String product, String issueType) {
        try {
            // Input Validation
            if (String.isBlank(name) || String.isBlank(email) || 
                String.isBlank(subject) || String.isBlank(description) ||
                String.isBlank(product) || String.isBlank(issueType)) {
                throw new AuraHandledException('All fields are required');
            }

            // Validate Email Format
            if (!isValidEmail(email)) {
                throw new AuraHandledException('Invalid email format');
            }

            // Create Case
            Case c = new Case();
            c.Subject = subject.trim();
            c.Description = description.trim();
            c.Origin = 'Web';
            c.Priority = 'Medium';
            c.Status = 'New';
            c.SuppliedName = name.trim();
            c.SuppliedEmail = email.trim();

            // Attempt to set custom fields if they exist (non-blocking)
            try {
                c.put('Product__c', product);
                c.put('Issue_Category__c', issueType);
            } catch (Exception e) {
                // Custom fields don't exist, but case can still be created
                System.debug('Custom fields not available: ' + e.getMessage());
            }

            // Insert the case
            insert c;

            System.debug('Case created successfully with ID: ' + c.Id);
            return c.Id;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error creating case: ' + e.getMessage());
            throw new AuraHandledException('Unable to create case: ' + e.getMessage());
        }
    }

    /**
     * Validate Email Address Format
     * @param email - Email to validate
     * @return Boolean - true if valid email format
     */
    private static Boolean isValidEmail(String email) {
        String emailPattern = '^[a-zA-Z0-9._%-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,4}$';
        Pattern p = Pattern.compile(emailPattern);
        Matcher m = p.matcher(email);
        return m.matches();
    }
}
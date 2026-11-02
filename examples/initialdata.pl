# Example of RT initial data, see https://docs.bestpractical.com/rt/latest/initialdata.html
#
# Mount it into the init directory to apply it on the first start:
#
#   docker run -v ./examples:/docker-entrypoint-init.d:ro ...
#
# or insert it into a running container:
#
#   docker exec -i rt rt-initdata - < examples/initialdata.pl

@Users = (
    {
        Name         => 'alice',
        Password     => 'alice-password',
        EmailAddress => 'alice@example.com',
        RealName     => 'Alice Example',
        Privileged   => 1,
    },
    {
        Name         => 'customer',
        Password     => 'customer-password',
        EmailAddress => 'customer@example.com',
        Privileged   => 0,
    },
);

@Groups = (
    {
        Name        => 'Staff',
        Description => 'Support staff',
        Members     => { Users => ['alice'] },
    },
);

@Queues = (
    {
        Name              => 'Support',
        Description       => 'Support requests',
        CorrespondAddress => 'support@example.com',
        CommentAddress    => 'support-comment@example.com',
    },
);

# REST2 can create custom fields, but not apply them to a queue
@CustomFields = (
    {
        Name       => 'Severity',
        Type       => 'SelectSingle',
        LookupType => 'RT::Queue-RT::Ticket',
        Queue      => ['General', 'Support'],
        Values     => [
            { Name => 'Low',  SortOrder => 1 },
            { Name => 'High', SortOrder => 2 },
        ],
    },
);

@ACL = (
    map {
        { GroupId => 'Staff', GroupDomain => 'UserDefined', Queue => 'Support', Right => $_ }
    } qw(SeeQueue ShowTicket CreateTicket ReplyToTicket CommentOnTicket OwnTicket ModifyTicket),
);

1;

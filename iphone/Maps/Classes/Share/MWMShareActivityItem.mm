#import "MWMShareActivityItem.h"
#import "Statistics.h"

#import "3party/Alohalytics/src/alohalytics_objc.h"

#include <CoreApi/Framework.h>
#import <CoreApi/PlacePageData.h>
#import <CoreApi/PlacePagePreviewData.h>
#import <CoreApi/PlacePageInfoData.h>

NSString * httpGe0Url(NSString * shortUrl)
{
  return
      [shortUrl stringByReplacingCharactersInRange:NSMakeRange(0, 6) withString:@"http://ge0.me/"];
}

@interface MWMShareActivityItem ()

@property(nonatomic) PlacePageData *data;
@property(nonatomic) CLLocationCoordinate2D location;
@property(nonatomic) BOOL isMyPosition;

@end

@implementation MWMShareActivityItem

- (instancetype)initForMyPositionAtLocation:(CLLocationCoordinate2D const &)location
{
  self = [super init];
  if (self)
  {
    _location = location;
    _isMyPosition = YES;
  }
  return self;
}

- (instancetype)initForPlacePageObject:(id<MWMPlacePageObject>)object
{
  NSAssert(false, @"deprecated");

  return nil;
}

- (instancetype)initForPlacePage:(PlacePageData *)data {
  self = [super init];
  if (self)
  {
    NSAssert(data, @"Entity can't be nil!");
    _isMyPosition = data.isMyPosition;
    _data = data;
  }
  return self;
}

- (NSString *)url:(BOOL)isShort
{
  auto & f = GetFramework();

  auto const title = ^NSString *(PlacePageData *data)
  {
    if (!data || data.isMyPosition)
      return L(@"core_my_position");
    else if (data.previewData.title.length > 0)
      return data.previewData.title;
    else if (data.previewData.subtitle.length)
      return data.previewData.subtitle;
    else if (data.previewData.address.length)
      return data.previewData.address;
    else
      return @"";
  };

  ms::LatLon const ll = self.data ? ms::LatLon(self.data.locationCoordinate.latitude,
                                               self.data.locationCoordinate.longitude)
                                    : ms::LatLon(self.location.latitude, self.location.longitude);
  std::string const & s = f.CodeGe0url(ll.m_lat, ll.m_lon, f.GetDrawScale(), title(self.data).UTF8String);

  NSString * url = @(s.c_str());
  if (!isShort)
    return url;
  NSUInteger const kGe0UrlLength = 16;
  return [url substringWithRange:NSMakeRange(0, kGe0UrlLength)];
}

#pragma mark - UIActivityItemSource

- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)activityViewController
{
  return [self url:YES];
}

- (id)activityViewController:(UIActivityViewController *)activityViewController
         itemForActivityType:(NSString *)activityType
{
  NSString * event = @"MWMShareLocationActivityItem:activityViewController:itemForActivityType:";
  NSString * type = activityType;
  [Statistics logEvent:kStatEventName(kStatShare, kStatLocation)
        withParameters:@{kStatAction : type}];
  [Alohalytics logEvent:event withValue:type];
  if ([UIActivityTypePostToTwitter isEqualToString:type])
    return self.itemForTwitter;
  return [self itemDefaultWithActivityType:type];
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController
              subjectForActivityType:(NSString *)activityType
{
  return [self subjectDefault];
}

#pragma mark - Message

- (NSString *)itemForTwitter
{
  NSString * shortUrl = [self url:YES];
  return [NSString stringWithFormat:@"%@\n%@", httpGe0Url(shortUrl),
                                    self.isMyPosition ? L(@"my_position_share_email_subject")
                                                      : self.data.previewData.title];
}

- (NSString *)itemDefaultWithActivityType:(NSString *)activityType
{
  NSString * ge0Url = [self url:NO];
  NSString * url = httpGe0Url(ge0Url);
  if (self.isMyPosition)
  {
    BOOL const hasSubject = [activityType isEqualToString:UIActivityTypeMail];
    if (hasSubject)
      return [NSString stringWithFormat:@"%@ %@", url, ge0Url];
    return [NSString
        stringWithFormat:@"%@ %@\n%@", L(@"my_position_share_email_subject"), url, ge0Url];
  }

  NSMutableString * result = [L(@"sharing_call_action_look") mutableCopy];
  std::vector<NSString *> strings{self.data.previewData.title,
                                 self.data.previewData.subtitle,
                                 self.data.previewData.address,
                                 self.data.infoData.phone,
                                 url,
                                 ge0Url};

  if (self.data.previewData.isBookingPlace)
  {
    strings.push_back(L(@"sharing_booking"));
    strings.push_back(self.data.sponsoredDescriptionURL);
  }

  for (auto const & str : strings)
  {
    if (str.length)
      [result appendString:[NSString stringWithFormat:@"\n%@", str]];
  }

  return result;
}

#pragma mark - Subject

- (NSString *)subjectDefault
{
  return self.isMyPosition ? L(@"my_position_share_email_subject")
                           : L(@"bookmark_share_email_subject");
}

@end

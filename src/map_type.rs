use juniper::GraphQLEnum;

/// A scenario selection. Board layout and rules will be implemented separately.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, GraphQLEnum)]
pub enum MapType {
    #[default]
    SupplyPoint,
}

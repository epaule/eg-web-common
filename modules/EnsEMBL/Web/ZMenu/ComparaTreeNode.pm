=head1 LICENSE

Copyright [2009-2014] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

# $Id: ComparaTreeNode.pm,v 1.13 2013-12-11 12:04:38 jk10 Exp $

package EnsEMBL::Web::ZMenu::ComparaTreeNode;

use strict;

use URI::Escape qw(uri_escape);
use IO::String;
use Bio::AlignIO;
use EnsEMBL::Web::TmpFile::Text;
use Data::Dumper;

use base qw(EnsEMBL::Web::ZMenu);

## EG : add 'ot' param to the tree navigation links 
sub content {
  my $self     = shift;
  my $cdb      = shift || 'compara';
  my $hub      = $self->hub;
  my $object   = $self->object;
  my $tree = $object->isa('EnsEMBL::Web::Object::GeneTree') ? $object->tree : $object->get_GeneTree($cdb);
  die 'No tree for gene' unless $tree;
  my $node_id  = $hub->param('node')                   || die 'No node value in params';
  my $node            = $tree->find_node_by_node_id($node_id);
  
  unless ($node) {
    $tree = $tree->tree->{'_supertree'};
    $node = $tree->find_node_by_node_id($node_id);
    die "No node_id $node_id in ProteinTree" unless $node;
  }
  
  my %collapsed_ids   = map { $_ => 1 } grep /\d/, split ',', $hub->param('collapse');
  my $ht              = $hub->param('ht') || undef;
  my $leaf_count      = scalar @{$node->get_all_leaves};
  my $is_leaf         = $node->is_leaf;
  my $is_root         = ($node->root eq $node);
  my $is_supertree    = ($node->tree->tree_type eq 'supertree');
  my $parent_distance = $node->distance_to_parent || 0;

  if ($is_leaf and $is_supertree) {
    my $child = $node->adaptor->fetch_node_by_node_id($node->{_subtree}->root_id);
    $node->add_tag('taxon_name', $child->get_tagvalue('taxon_name'));
    $node->add_tag('taxon_id', $child->get_tagvalue('taxon_id'));
    my $members = $node->adaptor->fetch_all_AlignedMember_by_root_id($child->node_id);
    $node->{_sub_leaves_count} = scalar(@$members);
    my $link_gene = $members->[0];
    foreach my $g (@$members) {
      $link_gene = $g if (lc $g->genome_db->name) eq (lc $hub->species);
    }
    $node->{_sub_reference_gene} = $link_gene->gene_member;
  }

  my $tagvalues       = $node->get_tagvalue_hash;
  my $taxon_id        = $tagvalues->{'taxon_id'};
     $taxon_id        = $node->genome_db->taxon_id if !$taxon_id && $is_leaf && not $is_supertree;
  my $taxon_name      = $tagvalues->{'taxon_name'};
     $taxon_name      = $node->genome_db->taxon->name if !$taxon_name && $is_leaf && not $is_supertree;
  my $taxon_mya       = $hub->species_defs->multi_hash->{'DATABASE_COMPARA'}{'TAXON_MYA'}->{$taxon_id};
  my $taxon_alias     = $hub->species_defs->multi_hash->{'DATABASE_COMPARA'}{'TAXON_NAME'}->{$taxon_id};
  my $caption         = 'Taxon: ';
 
  if (defined $taxon_alias) {
    $caption .= $taxon_alias;
    $caption .= sprintf ' ~%d MYA', $taxon_mya if defined $taxon_mya;
    $caption .= " ($taxon_name)" if defined $taxon_name;
  } elsif (defined $taxon_name) {
    $caption .= $taxon_name;
    $caption .= sprintf ' ~%d MYA', $taxon_mya if defined $taxon_mya;
  } else {
    $caption .= 'unknown';
  }
  
  $self->caption($caption);
  
  # Branch length
  $self->add_entry({
    type  => 'Branch Length',
    label => $parent_distance,
    order => 3
  }) unless $is_root;

  # Bootstrap
  $self->add_entry({
    type => 'Bootstrap',
    label => exists $tagvalues->{'bootstrap'} ? $tagvalues->{'bootstrap'} : 'NA',
    order => 4
  }) unless $is_root || $is_leaf || $is_supertree;

  if (defined $tagvalues->{'lost_taxon_id'}) {
    my $lost_taxa = $tagvalues->{'lost_taxon_id'};
       $lost_taxa = [ $lost_taxa ] if ref $lost_taxa ne 'ARRAY';
       
    $self->add_entry({
      type  => 'Lost taxa',
      label => join(', ', map {$hub->species_defs->multi_hash->{'DATABASE_COMPARA'}{'TAXON_NAME'}->{$_} || "taxon_id: $_"}  @$lost_taxa ),
      order => 5.6
    });
  }

  # Internal node_id
  $self->add_entry({
    type => 'node_id',
    label => $node->node_id,
    order => 13
  });
  
  my $action = 'Web/ComparaTree' . ($cdb =~ /pan/ ? '/pan_compara' : '');

  if (not $is_supertree) {

  # Expand all nodes
  if (grep $_ != $node_id, keys %collapsed_ids) {
    $self->add_entry({
      type  => 'Image',
      label => 'expand all sub-trees',
	    link_class => 'update_panel',
      order => 8,
      extra => { update_params => '<input type="hidden" class="update_url" name="collapse" value="none" />' },
      link  => $hub->url('Component',{
        type     => $hub->type,
        action   => $action,
        ht       => $ht,
        collapse => 'none'
      })
    });
  }

  # Collapse other nodes
  my @adjacent_subtree_ids = map $_->node_id, @{$node->get_all_adjacent_subtrees};
  
  if (grep !$collapsed_ids{$_}, @adjacent_subtree_ids) {
    my $collapse = join ',', keys %collapsed_ids, @adjacent_subtree_ids;
    
    $self->add_entry({
      type  => 'Image',
      label => 'collapse other nodes',
      link_class => 'update_panel',
      order => 10,
      extra => { update_params => qq{<input type="hidden" class="update_url" name="collapse" value="$collapse" />} },
      link  => $hub->url('Component',{
        type     => $hub->type,
        action   => $action,
        ht       => $ht,
        collapse => $collapse 
      })
    });
  }
  
  }

  if ($is_leaf and $is_supertree) {

      # Gene count
      $self->add_entry({
        type  => 'Gene Count',
        label => $node->{_sub_leaves_count},
        order => 2,
      });
    
      my $link_gene = $node->{_sub_reference_gene};

      $self->add_entry({
        type  => 'Gene',
        label => 'Switch to that tree',
        order => 11,
        link  => $hub->url({
          species  => $link_gene->genome_db->name,
          type     => 'Gene',
          action   => 'Compara_Tree',
          __clear  => 1,
          g        => $link_gene->stable_id,
        })
      }); 

  } elsif ($is_leaf) {
    # expand all paralogs
    my $gdb_id = $node->genome_db_id;
    my (%collapse_nodes, %expand_nodes);
    
    foreach my $leaf (@{$tree->get_all_leaves}) {
      if ($leaf->genome_db_id == $gdb_id) {
        $expand_nodes{$_->node_id}   = $_ for @{$leaf->get_all_ancestors};
        $collapse_nodes{$_->node_id} = $_ for @{$leaf->get_all_adjacent_subtrees};
      } 
    }
    
    my @collapse_node_ids = grep !$expand_nodes{$_}, keys %collapse_nodes;
    
    if (@collapse_node_ids) {
      my $collapse = join ',', @collapse_node_ids;
      
      $self->add_entry({
        type  => 'Image',
        label => 'show all paralogs',
        link_class => 'update_panel',
        order => 11,
        extra => { update_params => qq{<input type="hidden" class="update_url" name="collapse" value="$collapse" />} },
      link  => $hub->url('Component',{
          type     => $hub->type,
          action   => $action,
          ht       => $ht,
          collapse => $collapse 
        })
      }); 
    }
  } else {
    # Duplication confidence
    my $node_type = $tagvalues->{'node_type'};
    
    if (defined $node_type) {
      my $label;
         $label = 'Dubious duplication' if $node_type eq 'dubious';
         $label = sprintf 'Duplication (%d%s confid.)', 100 * ($tagvalues->{'duplication_confidence_score'} || 0), '%' if $node_type eq 'duplication';
      	 $label = 'Speciation' if $node_type eq 'speciation';
      	 $label = 'Gene split' if $node_type eq 'gene_split';
      
      $self->add_entry({
        type  => 'Type',
        label => $label,
        order => 5
      });
    }
    
    if (defined $tagvalues->{'tree_support'}) {
      my $tree_support = $tagvalues->{'tree_support'};
         $tree_support = [ $tree_support ] if ref $tree_support ne 'ARRAY';
      $self->add_entry({
        type  => 'Support',
        label => join(',', @$tree_support),
        order => 5.5
      });
    }

    if ($is_root and not $is_supertree) {
      # GeneTree StableID
      $self->add_entry({
        type  => 'GeneTree StableID',
        label => $node->tree->stable_id,
        order => 1
       });

      # Link to TreeFam Tree
      my $treefam_tree = 
        $tagvalues->{'treefam_id'}          || 
        $tagvalues->{'part_treefam_id'}     || 
        $tagvalues->{'cont_treefam_id'}     || 
        $tagvalues->{'dev_treefam_id'}      || 
        $tagvalues->{'dev_part_treefam_id'} || 
        $tagvalues->{'dev_cont_treefam_id'} || 
        undef;
      
      if (defined $treefam_tree) {
        foreach my $treefam_id (split ';', $treefam_tree) {
          my $treefam_link = $hub->get_ExtURL('TREEFAMTREE', $treefam_id);
          
          if ($treefam_link) {
            $self->add_entry({
              type  => 'Maps to TreeFam',
              label => $treefam_id,
              link  => $treefam_link,
              extra => { external => 1 },
              order => 6
            });
          }
        }
      }
    }
    
    # Gene count
    $self->add_entry({
      type  => $is_supertree ? 'Tree Count' : 'Gene Count',
      label => $leaf_count,
      order => 2
    });
    
    return if $is_supertree;
    
    if ($collapsed_ids{$node_id}) {
      my $collapse = join(',', grep $_ != $node_id, keys %collapsed_ids) || 'none';
      
      # Expand this node
      $self->add_entry({
        type  => 'Image',
        label => 'expand this sub-tree',
        link_class => 'update_panel',
        order => 7,
        extra => { update_params => qq{<input type="hidden" class="update_url" name="collapse" value="$collapse" />} },
        link  => $hub->url('Component',{
          type     => $hub->type,
          action   => $action,
          ht       => $ht,
          collapse => $collapse 
        })
      });
    } else {
      my $collapse = join ',', $node_id, keys %collapsed_ids;
      
      # Collapse this node
      $self->add_entry({
        type  => 'Image',
        label => 'collapse this node',
        link_class => 'update_panel',
        order => 9,
        extra => { update_params => qq{<input type="hidden" class="update_url" name="collapse" value="$collapse" />} },
        link  => $hub->url('Component',{
          type     => $hub->type,
          action   => $action,
          ht       => $ht,
          collapse => $collapse 
        })
      });
    }

    my $comparison_view_link = 1;
    $comparison_view_link = 0 if ($cdb =~ /pan/);

    if ($leaf_count <= 10) {
      my $url_params = { type => 'Location', action => 'Multi', r => undef };
      my $s = $self->hub->species eq 'Multi' ? 0 : 1;
      
      foreach (@{$node->get_all_leaves}) {
        my $gene = $_->gene_member->stable_id;
        
        next if $gene eq $hub->param('g');
        
        # FIXME: ucfirst tree->genome_db->name is a hack to get species names right.
        # There should be a way of retrieving this name correctly instead.
        if ($s == 0) {
          $url_params->{'species'} = ucfirst $_->genome_db->name;
          $url_params->{'g'} = $gene;
        } 
        else {
          $url_params->{"s$s"} = ucfirst $_->genome_db->name;
          $url_params->{"g$s"} = $gene;
        }
        $s++;
      }
      
      $self->add_entry({
        type  => 'Comparison',
        label => 'Jump to Region Comparison view',
        link  => $hub->url($url_params),
        order => 13
      }) if $comparison_view_link;
    }
    
    # Subtree dumps
    my ($url_align, $url_tree, $url_multi_align) = $self->dump_tree_as_text($node);
    
    $self->add_entry({
      type  => 'View Sub-tree',
      label => 'Alignment: FASTA',
      link  => $url_align,
      extra => { external => 1 },
      order => 14
    });
    
    $self->add_entry({
      type  => 'View Sub-tree',
      label => 'Alignment: ClustalW',
      link  => $url_multi_align,
      extra => { external => 1 },
      order => 15
    });
    
    $self->add_entry({
      type  => 'View Sub-tree',
      label => 'Tree: New Hampshire',
      link  => $url_tree,
      extra => { external => 1 },
      order => 16
    });
    
    # Jalview
    $self->add_entry({
      type  => 'View Sub-tree',
      label => 'Expand for Jalview',
      link_class => 'expand',
      order => 17,
      link  => $hub->url({
        type     => 'ZMenu',
        action   => 'Gene',
        function => 'Jalview',
        file     => uri_escape($url_align),
        treeFile => uri_escape($url_tree)
      })
    });
  }
}

# Takes a compara tree and dumps the alignment and tree as text files.
# Returns the urls of the files that contain the trees
sub dump_tree_as_text {
  my $self = shift;
  my $tree = shift || die 'Need a ProteinTree object';
  
  my $var_fasta; my $var_clustalw;
  my $file_fa = EnsEMBL::Web::TmpFile::Text->new(extension => 'fa', prefix => 'gene_tree');
  my $file_nh = EnsEMBL::Web::TmpFile::Text->new(extension => 'nh', prefix => 'gene_tree');
  my $file_aln = EnsEMBL::Web::TmpFile::Text->new(extension => 'txt', prefix => 'gene_tree');
  my $align   = $tree->get_SimpleAlign(-APPEND_SP_SHORT_NAME => 1);
  my $aio     = Bio::AlignIO->new(-format => 'fasta', -fh => IO::String->new($var_fasta));
  my $maio    = Bio::AlignIO->new(-format => 'clustalw', -fh => IO::String->new($var_clustalw));
  
  $align = $align->remove_gaps('-', 1);	# Uses a method in Bio::SimpleAlign to remove the columns which are gaps across all sequences
  $aio->write_aln($align); # Write the fasta alignment using BioPerl
  $maio->write_aln($align); # Write the ClustalW alignment using BioPerl
  
  print $file_fa $var_fasta;
  print $file_aln $var_clustalw;
  print $file_nh $tree->newick_format('full_web');
  
  $file_fa->save;
  $file_nh->save;
  $file_aln->save;
  
  return ($file_fa->URL, $file_nh->URL, $file_aln->URL);
}


1;

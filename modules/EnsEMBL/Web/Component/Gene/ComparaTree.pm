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

package EnsEMBL::Web::Component::Gene::ComparaTree;

use strict;
use warnings;

use Bio::EnsEMBL::Compara::DBSQL::XrefAssociationAdaptor;

sub content {
  my $self        = shift;
  my $cdb         = shift || $self->hub->param('cdb') || 'compara';
  my $hub         = $self->hub;
  my $object      = $self->object || $self->hub->core_object('gene');
  my $is_genetree = $object && $object->isa('EnsEMBL::Web::Object::GeneTree') ? 1 : 0;
  my ($gene, $member, $tree, $node, $test_tree);

  my $type   = $hub->param('data_type') || $hub->type;
  my $vc = $self->view_config($type);

## EG  
  my $url_function = $hub->function;
##

  if ($is_genetree) {
    $tree   = $object->Obj;
    $member = undef;
  } else {
    $gene = $object;
    ($member, $tree, $node, $test_tree) = $self->get_details($cdb);
  }

  return $tree . $self->genomic_alignment_links($cdb) if $hub->param('g') && !$is_genetree && !defined $member;

  my $leaves               = $tree->get_all_leaves;
  my $tree_stable_id       = $tree->tree->stable_id;
  my $highlight_gene       = $hub->param('g1');
  my $highlight_ancestor   = $hub->param('anc');

## EG 
  my $collapsed_nodes = $hub->param('collapse');
  # buggy parameter: "collapse=;" was taken to mean "collapse=none;"
  $hub->input->delete('collapse') unless $collapsed_nodes;
##

# EG add ht param
  my $unhighlight          = $highlight_gene ? $hub->url({action => 'Compara_Tree', function => $url_function, g1 => undef, collapse => $collapsed_nodes, ht => $hub->param('ht') }) : '';
  my $image_width          = $self->image_width       || 800;
  my $colouring            = $hub->param('colouring') || 'background';
  my $collapsability       = $is_genetree ? '' : ($vc->get('collapsability') || $hub->param('collapsability'));
  my $clusterset_id        = $vc->get('clusterset_id') || $hub->param('clusterset_id');
  my $show_exons           = $hub->param('exons') eq 'on' ? 1 : 0;
  my $image_config         = $hub->get_imageconfig('genetreeview');
  my @hidden_clades        = grep { $_ =~ /^group_/ && $hub->param($_) eq 'hide'     } $hub->param;
  my @collapsed_clades     = grep { $_ =~ /^group_/ && $hub->param($_) eq 'collapse' } $hub->param;
  my @highlights           = $gene && $member ? ($gene->stable_id, $member->genome_db->dbID) : (undef, undef);
  my $hidden_genes_counter = 0;
  my $link                 = $hub->type eq 'GeneTree' ? '' : sprintf ' <a href="%s">%s</a>', $hub->url({ species => 'Multi', type => 'GeneTree', action => 'Image', gt => $tree_stable_id, __clear => 1 }), $tree_stable_id;
  my (%hidden_genome_db_ids, $highlight_species, $highlight_genome_db_id);


  #EG: warning message is added to the top of the page to let the user know if an old GeneTree stable_ids is mapped to new GeneTree stable_ids
  my $html = $tree->history_warn ? $self->_warning('Warning', $tree->history_warn) : '';
  # EG summary table moved to new component

#  my $html                 = sprintf '<h3>GeneTree%s</h3>%s', $link, $self->new_twocol(
#    ['Number of genes',             scalar(@$leaves)                                                  ],
#    ['Number of speciation nodes',  $self->get_num_nodes_with_tag($tree, 'node_type', 'speciation')   ],
#    ['Number of duplication',       $self->get_num_nodes_with_tag($tree, 'node_type', 'duplication')  ],
#    ['Number of ambiguous',         $self->get_num_nodes_with_tag($tree, 'node_type', 'dubious')      ],
#    ['Number of gene split events', $self->get_num_nodes_with_tag($tree, 'node_type', 'gene_split')   ]
#  )->render;

  if ($highlight_gene) {
    my $highlight_gene_display_label;
    
    foreach my $this_leaf (@$leaves) {
      if ($highlight_gene && $this_leaf->gene_member->stable_id eq $highlight_gene) {
        $highlight_gene_display_label = $this_leaf->gene_member->display_label || $highlight_gene;
        $highlight_species            = $this_leaf->gene_member->genome_db->name;
        $highlight_genome_db_id       = $this_leaf->gene_member->genome_db_id;
        last;
      }
    }

    if ($member && $gene && $highlight_species) {
      $html .= $self->_info('Highlighted genes',
        sprintf(
          '<p>In addition to all <I>%s</I> genes, the %s gene (<I>%s</I>) and its paralogues have been highlighted. <a href="%s">Click here to switch off highlighting</a>.</p>', 
          $member->genome_db->name, 
          $highlight_gene_display_label,
          $highlight_species, 
          $unhighlight
        )
      );
    } else {
      $html .= $self->_warning('WARNING', "<p>$highlight_gene gene is not in this Gene Tree</p>");
      $highlight_gene = undef;
    }
  }
  
  # Get all the genome_db_ids in each clade
  # Ideally, this should be stored in $hub->species_defs->multi_hash->{'DATABASE_COMPARA'}
  # or any other centralized place, to avoid recomputing it many times
  my %genome_db_ids_by_clade = map {$_ => []} @{ $self->hub->species_defs->TAXON_ORDER };
  foreach my $species_name (keys %{$self->hub->get_species_info}) {
    foreach my $clade (@{ $self->hub->species_defs->get_config($species_name, 'SPECIES_GROUP_HIERARCHY') }) {
      push @{$genome_db_ids_by_clade{$clade}}, $hub->species_defs->multi_hash->{'DATABASE_COMPARA'}{'GENOME_DB'}{lc $species_name};
    }
  }
  $genome_db_ids_by_clade{LOWCOVERAGE} = $self->hub->species_defs->multi_hash->{'DATABASE_COMPARA'}{'SPECIES_SET'}{'LOWCOVERAGE'};

  if (@hidden_clades) {
    %hidden_genome_db_ids = ();
    
    foreach my $clade (@hidden_clades) {
      my ($clade_name) = $clade =~ /group_([\w\-]+)_display/;
      $hidden_genome_db_ids{$_} = 1 for @{ $genome_db_ids_by_clade{$clade_name} };
    }
    
    foreach my $this_leaf (@$leaves) {
      my $genome_db_id = $this_leaf->genome_db_id;
      
      next if $highlight_genome_db_id && $genome_db_id eq $highlight_genome_db_id;
      next if $highlight_gene && $this_leaf->gene_member->stable_id eq $highlight_gene;
      next if $member && $genome_db_id == $member->genome_db_id;
      
      if ($hidden_genome_db_ids{$genome_db_id}) {
        $hidden_genes_counter++;
        $this_leaf->disavow_parent;
        $tree = $tree->minimize_tree;
      }
    }

    $html .= $self->_info('Hidden genes', "<p>There are $hidden_genes_counter hidden genes in the tree. Use the 'configure page' link in the left panel to change the options.</p>") if $hidden_genes_counter;
  }

  $image_config->set_parameters({
    container_width => $image_width,
    image_width     => $image_width,
    slice_number    => '1|1',
    cdb             => $cdb
  });
  
  # Keep track of collapsed nodes
  my ($collapsed_to_gene, $collapsed_to_para);
  
  if (!$is_genetree) {
    $collapsed_to_gene = $self->collapsed_nodes($tree, $node, 'gene',     $highlight_genome_db_id, $highlight_gene);
    $collapsed_to_para = $self->collapsed_nodes($tree, $node, 'paralogs', $highlight_genome_db_id, $highlight_gene);
  }
  
  my $collapsed_to_dups = $self->collapsed_nodes($tree, undef, 'duplications', $highlight_genome_db_id, $highlight_gene);

  if (!defined $collapsed_nodes) { # Examine collapsabilty
    $collapsed_nodes = $collapsed_to_gene if $collapsability eq 'gene';
    $collapsed_nodes = $collapsed_to_para if $collapsability eq 'paralogs';
    $collapsed_nodes = $collapsed_to_dups if $collapsability eq 'duplications';
    $collapsed_nodes ||= '';
  }

  if (@collapsed_clades) {
    foreach my $clade (@collapsed_clades) {
      my ($clade_name) = $clade =~ /group_([\w\-]+)_display/;
      my $extra_collapsed_nodes = $self->find_nodes_by_genome_db_ids($tree, $genome_db_ids_by_clade{$clade_name}, 'internal');
      
      if (%$extra_collapsed_nodes) {
        $collapsed_nodes .= ',' if $collapsed_nodes;
        $collapsed_nodes .= join ',', keys %$extra_collapsed_nodes;
      }
    }
  }

  my $coloured_nodes;
  
  if ($colouring =~ /^(back|fore)ground$/) {
    my $mode   = $1 eq 'back' ? 'bg' : 'fg';

    # TAXON_ORDER is ordered by increasing phylogenetic size. Reverse it to
    # get the largest clades first, so that they can be overwritten later
    # (see ensembl-webcode/modules/EnsEMBL/Draw/GlyphSet/genetree.pm)
    foreach my $clade_name (reverse @{ $self->hub->species_defs->TAXON_ORDER }) {
      next unless $hub->param("group_${clade_name}_${mode}colour");
      my $genome_db_ids = $genome_db_ids_by_clade{$clade_name};
      my $colour        = $hub->param("group_${clade_name}_${mode}colour");
      my $nodes         = $self->find_nodes_by_genome_db_ids($tree, $genome_db_ids, $mode eq 'fg' ? 'all' : undef);
      
      push @$coloured_nodes, { clade => $clade_name,  colour => $colour, mode => $mode, node_ids => [ keys %$nodes ] } if %$nodes;
    }
  }

  push @highlights, $collapsed_nodes        || undef;
  push @highlights, $coloured_nodes         || undef;
  push @highlights, $highlight_genome_db_id || undef;
  push @highlights, $highlight_gene         || undef;
  push @highlights, $highlight_ancestor     || undef;
  push @highlights, $show_exons;

    # EG
    my @highlight_tags             = split(',',$hub->param('ht') || "");
    my $highlight_map = $self->get_highlight_map($cdb,$tree->tree);
    #my @compara_highlights; # not to be confused with COMPARA_HIGHLIGHTS list
    foreach my $ot_map (@$highlight_map){
      my $xref = $ot_map->{'xref'};
      if ( grep /^$xref$/, @highlight_tags ){
        push (@highlights, 
          sprintf("%s,%s,%s", $xref, $ot_map->{'colour'}, join(',', @{$ot_map->{'members'}})) 
        );
      }
    }
    #my $compara_highlights_str = join(';',@compara_highlights);

  my $image = $self->new_image($tree, $image_config, \@highlights);
  
  return if $self->_export_image($image, 'no_text');

  my $image_id = $gene ? $gene->stable_id : $tree_stable_id;
  my $li_tmpl  = '<li><a href="%s">%s</a></li>';
  my @view_links;


  $image->image_type        = 'genetree';
  $image->image_name        = ($hub->param('image_width')) . "-$image_id";
  $image->imagemap          = 'yes';
  $image->{'panel_number'}  = 'tree';

  ## Need to pass gene name to export form 
  my $gene_name;
  if ($gene) {
    my $dxr    = $gene->Obj->can('display_xref') ? $gene->Obj->display_xref : undef;
    $gene_name = $dxr ? $dxr->display_id : $gene->stable_id;
  }
  else {
    $gene_name = $tree_stable_id;
  }

  ## Parameters to pass into export form
  $image->{'export_params'} = [['gene_name', $gene_name],['align', 'tree'],['cdb', $cdb]];
  my @extra_params = qw(g1 anc collapse);
  foreach (@extra_params) {
    push @{$image->{'export_params'}}, [$_, $hub->param($_)];
  }
  foreach ($hub->param) {
    if (/^group/) {
      push @{$image->{'export_params'}}, [$_, $hub->param($_)];
    }
  }
  $image->{'data_export'}   = 'GeneTree';
  $image->{'remove_reset'}  = 1;

  $image->set_button('drag', 'title' => 'Drag to select region');

# EG include the ht param
  if ($gene) {
    push @view_links, sprintf $li_tmpl, $hub->url({ action => 'Compara_Tree', function => $url_function, ht => $hub->param('ht'), collapse => $collapsed_to_gene, g1 => $highlight_gene }), $highlight_gene ? 'View current genes only'        : 'View current gene only';
    push @view_links, sprintf $li_tmpl, $hub->url({ action => 'Compara_Tree', function => $url_function, ht => $hub->param('ht'), collapse => $collapsed_to_para || undef, g1 => $highlight_gene }), $highlight_gene ? 'View paralogs of current genes' : 'View paralogs of current gene';
  }

  push @view_links, sprintf $li_tmpl, $hub->url({ action => 'Compara_Tree', function => $url_function, ht => $hub->param('ht'), collapse => $collapsed_to_dups, g1 => $highlight_gene }), 'View all duplication nodes';
  push @view_links, sprintf $li_tmpl, $hub->url({ action => 'Compara_Tree', function => $url_function, ht => $hub->param('ht'), collapse => 'none', g1 => $highlight_gene }), 'View fully expanded tree';
  push @view_links, sprintf $li_tmpl, $unhighlight, 'Switch off highlighting' if $highlight_gene;
# /EG

  {
    my @rank_options = ( q{<option value="/">-- Select a rank--</option>} );
    my $selected_rank = $hub->param('gtr') || '';
    foreach my $rank (qw(species genus family order class phylum kingdom)) {
      my $collapsed_to_rank = $self->collapsed_nodes($tree, $node, "rank_$rank", $highlight_genome_db_id, $highlight_gene);
      push @rank_options, sprintf qq{<option value="%s" %s>%s</option>\n}, $hub->url({ collapse => $collapsed_to_rank, g1 => $highlight_gene, gtr => $rank }), $rank eq $selected_rank ? 'selected' : '', ucfirst $rank;
    }
    push @view_links, sprintf qq{<li>Collapse all the nodes at the taxonomic rank <select onchange="Ensembl.redirect(this.value)">%s</select></li>}, join("\n", @rank_options);
  }

  $html .= $image->render;
  $html .= sprintf(qq{
    <div>
      <h4>View options:</h4>
      <ul>%s</ul>
      <p>Use the 'configure page' link in the left panel to set the default. Further options are available from menus on individual tree nodes.</p>
    </div>
  }, join '', @view_links);
  
  return $html;
}

sub content_align {
    my $self = shift;
    my $cdb  = shift || 'compara';
    my $hub  = $self->hub;

  # Get the ProteinTree object
    my ($member, $tree, $node) = $self->get_details($cdb);

    return $tree . $self->genomic_alignment_links($cdb) unless defined $member;

  # Determine the format
    my %formats = EnsEMBL::Web::Constants::ALIGNMENT_FORMATS;
    my $mode    = $hub->param('text_format');
    $mode       = 'fasta' unless $formats{$mode};

    my $formatted; # Variable to hold the formatted alignment string
    my $fh  = new IO::Scalar(\$formatted);
    my $aio = new Bio::AlignIO( -format => $mode, -fh => $fh );
## EG : append species short name for clarity
    $aio->write_aln( $tree->get_SimpleAlign(-APPEND_SP_SHORT_NAME => 1) );
## EG

    return $hub->param('_format') eq 'Text' ? $formatted : sprintf(q{
    <p>Multiple sequence alignment in "<i>%s</i>" format:</p>
    <p>The sequence alignment format can be configured using the
    'configure page' link in the left panel.<p>
    <pre>%s</pre>
}, $formats{$mode} || $mode, $formatted);
}

sub get_highlight_map{
  my ($self, $cdb_name, $tree) = @_;
  my $hub         = $self->hub;
  my $object      = $self->object || $self->hub->core_object('gene');
  return [] if ($hub->species =~ /^multi$/i);
  if(exists $object->{'highlight_map'}){
    return $object->{'highlight_map'};
  }
  my @mapped_terms;
  my $colour = 'acef9b';
  my @compara_highlights = @{$hub->species_defs->COMPARA_HIGHLIGHTS || [] };
  return [] unless scalar @compara_highlights;
  my $adaptor = undef;
  eval{
    my $cdb = $object->database($cdb_name);
    $adaptor = Bio::EnsEMBL::Compara::DBSQL::XrefAssociationAdaptor->new($cdb);
  };
  return [] unless $adaptor;
  my $dbe = $hub->get_adaptor('get_DBEntryAdaptor');
  my $goadaptor = $hub->get_databases('go')->{'go'};
  my $goa = $goadaptor->get_OntologyTermAdaptor;
  for my $db_name (@compara_highlights){
    for my $xref (@{$adaptor->get_associated_xrefs_for_tree($tree,$db_name)}) {
      my $entry = $dbe->fetch_by_db_accession($db_name,$xref);
      my $desc;
      $desc = $entry->description if($entry);
      if(!$desc && $db_name =~ /^GO$/i){
        my $term   = $goa->fetch_by_accession($xref); 
        $desc = $term->name || $term->definition;
      }
      my @members = map { $_->stable_id } @{$adaptor->get_members_for_xref($tree,$xref,$db_name)};
      push (@mapped_terms,{ xref=>$xref, db_name=>$db_name, members=>\@members, colour=>$colour, desc=>$desc});
    }
  }
  $object->{'highlight_map'} = \@mapped_terms;
  return \@mapped_terms;
}

1;
